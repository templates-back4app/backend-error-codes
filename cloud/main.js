// Stack: Node.js 22.x | Parse Server 7.x | File: cloud/main.js
// The Cloud Code behind the codes reproduce.sh triggers: 142 (validation), 206 (session missing),
// 119 (operation forbidden), 209 (invalid session token) and 141 (a plain error thrown inside a hook).
// It is the union of the two files deployed on the backends the article measured:
// user-auth-starter (the _User hook and whoami) and lockdown-lab (the Note hook and moderatorList).

// 142 · VALIDATION_ERROR — a beforeSave on _User that rejects short usernames and missing e-mails.
Parse.Cloud.beforeSave(Parse.User, (request) => {
  const user = request.object;
  const email = (user.get("email") ?? "").trim().toLowerCase();
  if (!email) throw new Parse.Error(Parse.Error.VALIDATION_ERROR, "an e-mail address is required.");
  user.set("email", email);
  const username = (user.get("username") ?? "").trim();
  if (username.length < 3) throw new Parse.Error(Parse.Error.VALIDATION_ERROR, "username needs at least 3 characters.");
  user.set("username", username);
});

// 209 · INVALID_SESSION_TOKEN — a Cloud Function that refuses to run without a logged-in caller.
Parse.Cloud.define("whoami", async (request) => {
  if (!request.user) throw new Parse.Error(Parse.Error.INVALID_SESSION_TOKEN, "log in first.");
  return { id: request.user.id, username: request.user.get("username"), verified: request.user.get("emailVerified") === true };
});

// 206 · SESSION_MISSING — a beforeSave on Note that needs a user to stamp the owner ACL.
// 141 · SCRIPT_FAILED — if `owner` arrives as a plain object, new Parse.ACL(owner) throws a TypeError; the
// backend wraps any non-Parse error thrown by a hook in code 141 and passes the message through.
Parse.Cloud.beforeSave("Note", (request) => {
  const note = request.object;
  if (!note.isNew()) return;
  const owner = request.user ?? note.get("owner");
  if (!owner) throw new Parse.Error(Parse.Error.SESSION_MISSING, "log in to create a note.");
  const acl = new Parse.ACL(owner);
  note.setACL(acl);
  note.set("owner", owner);
});

// 119 · OPERATION_FORBIDDEN — a Cloud Function that only members of the "moderator" role may call.
Parse.Cloud.define("moderatorList", async (request) => {
  if (!request.user) throw new Parse.Error(Parse.Error.INVALID_SESSION_TOKEN, "log in first.");
  const isMod = await new Parse.Query(Parse.Role).equalTo("name", "moderator").equalTo("users", request.user).first({ useMasterKey: true });
  if (!isMod) throw new Parse.Error(Parse.Error.OPERATION_FORBIDDEN, "moderators only.");
  const notes = await new Parse.Query("Note").find({ useMasterKey: true });
  return notes.map((n) => ({ id: n.id, text: n.get("text"), owner: n.get("owner")?.id }));
});
