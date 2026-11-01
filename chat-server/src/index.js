import cors from "cors";
import express from "express";
import pg from "pg";

const { Pool } = pg;

const port = Number(process.env.PORT || 3004);
const databaseUrl =
  process.env.DATABASE_URL ||
  "postgres://global_village_chat:global_village_chat@localhost:5435/global_village_chat";
const authMeUrl =
  process.env.AUTH_API_ME_URL || "http://localhost:3002/auth/me";

const pool = new Pool({ connectionString: databaseUrl });
const app = express();

app.use(cors());
app.use(express.json({ limit: "5mb" }));

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

async function verifyToken(header) {
  if (!header || !/^Bearer \S+$/.test(header)) {
    return null;
  }
  let response;
  try {
    response = await fetch(authMeUrl, {
      headers: { Authorization: header },
      signal: AbortSignal.timeout(8000),
    });
  } catch (_) {
    return null;
  }
  if (!response.ok) return null;
  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    return null;
  }
  const user = payload?.user;
  if (!user || typeof user.id !== "string" || !user.id) return null;
  return user;
}

async function requireAuth(req, res, next) {
  const user = await verifyToken(req.headers.authorization || "");
  if (!user) {
    res.status(401).json({ error: "Please sign in to use chat." });
    return;
  }
  req.user = user;
  next();
}

function chatUserRow(row) {
  return {
    id: row.user_id,
    fullName: row.full_name,
    username: row.username,
    email: row.email,
    googlePhotoUrl: row.google_photo_url,
    interest: row.interest,
    authProvider: row.auth_provider,
  };
}

async function upsertChatUser(user) {
  await pool.query(
    `INSERT INTO chat_users (user_id, full_name, username, email, google_photo_url, interest, auth_provider, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,now())
     ON CONFLICT (user_id)
     DO UPDATE SET full_name = $2, username = $3, email = $4,
       google_photo_url = $5, interest = $6, auth_provider = $7, updated_at = now()`,
    [
      user.id,
      clean(user.fullName),
      clean(user.username) || null,
      clean(user.email) || null,
      clean(user.googlePhotoUrl) || null,
      clean(user.interest) || null,
      clean(user.authProvider) || "local",
    ],
  );
}

async function findFriendship(a, b) {
  const result = await pool.query(
    `SELECT * FROM friendships
     WHERE (requester_id = $1 AND addressee_id = $2)
        OR (requester_id = $2 AND addressee_id = $1)
     LIMIT 1`,
    [a, b],
  );
  return result.rows[0] || null;
}

async function areFriends(a, b) {
  const result = await pool.query(
    `SELECT 1 FROM friendships
     WHERE status = 'accepted'
       AND ((requester_id = $1 AND addressee_id = $2)
         OR (requester_id = $2 AND addressee_id = $1))
     LIMIT 1`,
    [a, b],
  );
  return result.rows.length > 0;
}

function messageJson(row) {
  return {
    id: row.id,
    senderId: row.sender_id,
    receiverId: row.receiver_id,
    contentType: row.content_type,
    text: row.text,
    voiceData: row.voice_data,
    voiceMimeType: row.voice_mime_type,
    voiceDuration: row.voice_duration,
    readAt: row.read_at,
    createdAt: row.created_at,
  };
}

function groupMessageJson(row) {
  return {
    id: row.id,
    groupId: row.group_id,
    senderId: row.sender_id,
    senderName: row.sender_name,
    contentType: row.content_type,
    text: row.text,
    voiceData: row.voice_data,
    voiceMimeType: row.voice_mime_type,
    voiceDuration: row.voice_duration,
    createdAt: row.created_at,
  };
}

async function isGroupMember(groupId, userId) {
  if (!groupId || !userId) return false;
  const result = await pool.query(
    `SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2 LIMIT 1`,
    [groupId, userId],
  );
  return result.rows.length > 0;
}

function parseMessageBody(body) {
  const text = clean(body.text).slice(0, 2000);
  const isLocation = body.isLocation === true;
  const isVoice = body.isVoice === true;
  const voiceData = isVoice ? (body.voiceData || "") : null;
  const voiceMimeType = isVoice ? clean(body.voiceMimeType) : null;
  const voiceDuration = isVoice ? Number(body.voiceDuration) || 0 : 0;
  return { text, isLocation, isVoice, voiceData, voiceMimeType, voiceDuration };
}

app.get("/health", async (_req, res, next) => {
  try {
    await pool.query("SELECT 1");
    res.json({ ok: true, service: "global-village-chat-api" });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/friends/requests", requireAuth, async (req, res, next) => {
  try {
    const me = req.user;
    const target = {
      id: clean(req.body.userId),
      fullName: clean(req.body.fullName),
      username: clean(req.body.username),
      email: clean(req.body.email),
      googlePhotoUrl: clean(req.body.googlePhotoUrl),
      interest: clean(req.body.interest),
      authProvider: clean(req.body.authProvider),
    };
    const message = clean(req.body.message).slice(0, 200);
    if (!target.id || target.id === me.id) {
      res.status(400).json({ error: "A valid target user is required." });
      return;
    }

    await upsertChatUser(me);
    await upsertChatUser(target);

    const existing = await findFriendship(me.id, target.id);
    if (existing) {
      if (existing.status === "accepted") {
        res.json({ status: "accepted" });
        return;
      }
      if (existing.requester_id === target.id) {
        await pool.query(
          `UPDATE friendships SET status = 'accepted', updated_at = now() WHERE id = $1`,
          [existing.id],
        );
        res.json({ status: "accepted" });
        return;
      }
      await pool.query(
        `UPDATE friendships SET message = $2, updated_at = now() WHERE id = $1`,
        [existing.id, message || existing.message],
      );
      res.json({ status: "pending" });
      return;
    }

    await pool.query(
      `INSERT INTO friendships (requester_id, addressee_id, status, message)
       VALUES ($1, $2, 'pending', $3)`,
      [me.id, target.id, message || null],
    );
    res.status(201).json({ status: "pending" });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/friends/accepts", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const requester = clean(req.body.userId);
    if (!requester) {
      res.status(400).json({ error: "A valid user id is required." });
      return;
    }
    const result = await pool.query(
      `UPDATE friendships
       SET status = 'accepted', updated_at = now()
       WHERE requester_id = $1 AND addressee_id = $2 AND status = 'pending'
       RETURNING id`,
      [requester, me],
    );
    if (result.rows.length === 0) {
      res.status(404).json({ error: "No pending friend request from this user." });
      return;
    }
    res.json({ status: "accepted" });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/friends/declines", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const requester = clean(req.body.userId);
    if (!requester) {
      res.status(400).json({ error: "A valid user id is required." });
      return;
    }
    const result = await pool.query(
      `DELETE FROM friendships
       WHERE requester_id = $1 AND addressee_id = $2 AND status = 'pending'
       RETURNING id`,
      [requester, me],
    );
    if (result.rows.length === 0) {
      res.status(404).json({ error: "No pending friend request from this user." });
      return;
    }
    res.json({ status: "declined" });
  } catch (error) {
    next(error);
  }
});

app.get("/chat/friends", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const friends = await pool.query(
      `SELECT u.*, f.status
       FROM friendships f
       JOIN chat_users u
         ON u.user_id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
       WHERE f.status = 'accepted' AND (f.requester_id = $1 OR f.addressee_id = $1)
       ORDER BY u.full_name`,
      [me],
    );
    const incoming = await pool.query(
      `SELECT u.*, f.message, f.created_at
       FROM friendships f
       JOIN chat_users u ON u.user_id = f.requester_id
       WHERE f.status = 'pending' AND f.addressee_id = $1
       ORDER BY f.created_at DESC`,
      [me],
    );
    const outgoing = await pool.query(
      `SELECT u.*, f.message, f.created_at
       FROM friendships f
       JOIN chat_users u ON u.user_id = f.addressee_id
       WHERE f.status = 'pending' AND f.requester_id = $1
       ORDER BY f.created_at DESC`,
      [me],
    );
    res.json({
      friends: friends.rows.map(chatUserRow),
      incoming: incoming.rows.map((r) => ({
        ...chatUserRow(r),
        message: r.message,
        createdAt: r.created_at,
      })),
      outgoing: outgoing.rows.map((r) => ({
        ...chatUserRow(r),
        message: r.message,
        createdAt: r.created_at,
      })),
    });
  } catch (error) {
    next(error);
  }
});

app.get("/chat/conversations", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const result = await pool.query(
      `SELECT u.user_id, u.full_name, u.username, u.email,
              u.google_photo_url, u.interest, u.auth_provider,
              lm.id AS last_message_id, lm.content_type AS last_type,
              lm.text AS last_text, lm.created_at AS last_at,
              lm.sender_id AS last_sender,
              COALESCE(unread.cnt, 0) AS unread_count
       FROM friendships f
       JOIN chat_users u
         ON u.user_id = CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
       LEFT JOIN LATERAL (
         SELECT m.* FROM chat_messages m
         WHERE (m.sender_id = $1 AND m.receiver_id = u.user_id)
            OR (m.sender_id = u.user_id AND m.receiver_id = $1)
         ORDER BY m.created_at DESC LIMIT 1
       ) lm ON true
       LEFT JOIN LATERAL (
         SELECT count(*)::int AS cnt FROM chat_messages m
         WHERE m.sender_id = u.user_id AND m.receiver_id = $1 AND m.read_at IS NULL
       ) unread ON true
       WHERE f.status = 'accepted' AND (f.requester_id = $1 OR f.addressee_id = $1)
       ORDER BY lm.created_at DESC NULLS LAST, u.full_name`,
      [me],
    );
    const groups = await pool.query(
      `SELECT g.id AS group_id, g.name AS group_name, g.created_by,
              (SELECT count(*)::int FROM group_members gm WHERE gm.group_id = g.id) AS member_count,
              lm.id AS last_message_id, lm.content_type AS last_type,
              lm.text AS last_text, lm.created_at AS last_at,
              lm.sender_id AS last_sender,
              COALESCE(unread.cnt, 0) AS unread_count
       FROM group_members my
       JOIN group_chats g ON g.id = my.group_id
       LEFT JOIN LATERAL (
         SELECT m.* FROM group_messages m
         WHERE m.group_id = g.id
         ORDER BY m.created_at DESC LIMIT 1
       ) lm ON true
       LEFT JOIN LATERAL (
         SELECT count(*)::int AS cnt FROM group_messages m2
         WHERE m2.group_id = g.id
           AND m2.sender_id <> $1
           AND m2.created_at > my.last_read_at
       ) unread ON true
       WHERE my.user_id = $1
       ORDER BY lm.created_at DESC NULLS LAST, g.name`,
      [me],
    );
    res.json({
      conversations: result.rows.map((r) => ({
        user: chatUserRow(r),
        lastMessage: r.last_message_id
          ? {
              text: r.last_text,
              contentType: r.last_type,
              createdAt: r.last_at,
              fromMe: r.last_sender === me,
            }
          : null,
        unreadCount: r.unread_count,
      })),
      groups: groups.rows.map((r) => ({
        id: r.group_id,
        name: r.group_name,
        memberCount: r.member_count,
        createdBy: r.created_by,
        lastMessage: r.last_message_id
          ? {
              text: r.last_text,
              contentType: r.last_type,
              createdAt: r.last_at,
              fromMe: r.last_sender === me,
            }
          : null,
        unreadCount: r.unread_count,
      })),
    });
  } catch (error) {
    next(error);
  }
});

app.get("/chat/messages/:userId", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const other = clean(req.params.userId);
    if (!other || !(await areFriends(me, other))) {
      res.status(403).json({ error: "You can only chat with accepted friends." });
      return;
    }
    const result = await pool.query(
      `SELECT * FROM chat_messages
       WHERE (sender_id = $1 AND receiver_id = $2)
          OR (sender_id = $2 AND receiver_id = $1)
       ORDER BY created_at ASC
       LIMIT 500`,
      [me, other],
    );
    res.json({ messages: result.rows.map(messageJson) });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/messages", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const to = clean(req.body.toUserId);
    const text = clean(req.body.text).slice(0, 2000);
    const isLocation = req.body.isLocation === true;
    const isVoice = req.body.isVoice === true;
    const voiceData = isVoice ? (req.body.voiceData || "") : null;
    const voiceMimeType = isVoice ? clean(req.body.voiceMimeType) : null;
    const voiceDuration = isVoice ? Number(req.body.voiceDuration) || 0 : 0;

    if (!to || !(await areFriends(me, to))) {
      res.status(403).json({ error: "You can only chat with accepted friends." });
      return;
    }
    if (!isVoice && !text) {
      res.status(400).json({ error: "Message text is required." });
      return;
    }
    if (isVoice && (!voiceData || voiceDuration < 1)) {
      res.status(400).json({ error: "Voice message data is required." });
      return;
    }

    const contentType = isVoice ? "voice" : isLocation ? "location" : "text";
    const result = await pool.query(
      `INSERT INTO chat_messages (
         sender_id, receiver_id, content_type, text,
         voice_data, voice_mime_type, voice_duration
       ) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [me, to, contentType, isVoice ? "Voice message" : text, voiceData, voiceMimeType, voiceDuration],
    );
    res.status(201).json({ message: messageJson(result.rows[0]) });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/messages/:userId/read", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const other = clean(req.params.userId);
    await pool.query(
      `UPDATE chat_messages SET read_at = now()
       WHERE sender_id = $1 AND receiver_id = $2 AND read_at IS NULL`,
      [other, me],
    );
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups", requireAuth, async (req, res, next) => {
  try {
    const me = req.user;
    await upsertChatUser(me);
    const rawIds = Array.isArray(req.body.memberIds) ? req.body.memberIds : [];
    const memberIds = [
      ...new Set(
        rawIds.map((v) => clean(v)).filter(Boolean).filter((id) => id !== me.id),
      ),
    ];
    const name = clean(req.body.name).slice(0, 60);
    if (memberIds.length === 0) {
      res.status(400).json({ error: "Select at least one friend to start a group chat." });
      return;
    }
    for (const id of memberIds) {
      if (!(await areFriends(me.id, id))) {
        res.status(403).json({ error: "You can only add accepted friends to a group." });
        return;
      }
    }
    const created = await pool.query(
      `INSERT INTO group_chats (name, created_by) VALUES ($1, $2) RETURNING id, created_by`,
      [name || "", me.id],
    );
    const groupId = created.rows[0].id;
    const allMemberIds = [me.id, ...memberIds];
    await pool.query(
      `INSERT INTO group_members (group_id, user_id)
       SELECT $1, x FROM unnest($2::uuid[]) AS x`,
      [groupId, allMemberIds],
    );
    let groupName = name;
    if (!groupName) {
      const names = await pool.query(
        `SELECT u.full_name FROM group_members gm
         JOIN chat_users u ON u.user_id = gm.user_id
         WHERE gm.group_id = $1 AND gm.user_id <> $2
         ORDER BY u.full_name`,
        [groupId, me.id],
      );
      groupName = names.rows.map((r) => r.full_name).filter(Boolean).join(", ").slice(0, 60) || "Group chat";
      await pool.query(`UPDATE group_chats SET name = $1 WHERE id = $2`, [groupName, groupId]);
    }
    res.status(201).json({
      group: {
        id: groupId,
        name: groupName,
        memberCount: allMemberIds.length,
        createdBy: created.rows[0].created_by,
      },
    });
  } catch (error) {
    next(error);
  }
});

app.get("/chat/groups/:groupId", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    if (!(await isGroupMember(groupId, me))) {
      res.status(403).json({ error: "You are not a member of this group." });
      return;
    }
    const group = await pool.query(
      `SELECT id, name, created_by FROM group_chats WHERE id = $1 LIMIT 1`,
      [groupId],
    );
    if (group.rows.length === 0) {
      res.status(404).json({ error: "Group not found." });
      return;
    }
    const members = await pool.query(
      `SELECT gm.user_id AS member_id, u.*, gm.joined_at
       FROM group_members gm
       LEFT JOIN chat_users u ON u.user_id = gm.user_id
       WHERE gm.group_id = $1
       ORDER BY gm.joined_at ASC`,
      [groupId],
    );
    res.json({
      group: {
        id: group.rows[0].id,
        name: group.rows[0].name,
        createdBy: group.rows[0].created_by,
        members: members.rows.map((r) =>
          chatUserRow({
            ...r,
            user_id: r.member_id,
            full_name: r.full_name || "Member",
          }),
        ),
      },
    });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups/:groupId/members", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    if (!(await isGroupMember(groupId, me))) {
      res.status(403).json({ error: "You are not a member of this group." });
      return;
    }
    const rawIds = Array.isArray(req.body.userIds) ? req.body.userIds : [];
    const userIds = [
      ...new Set(
        rawIds.map((v) => clean(v)).filter(Boolean).filter((id) => id !== me.id),
      ),
    ];
    if (userIds.length === 0) {
      res.status(400).json({ error: "Select at least one friend to invite." });
      return;
    }
    for (const id of userIds) {
      if (!(await areFriends(me, id))) {
        res.status(403).json({ error: "You can only invite accepted friends to a group." });
        return;
      }
    }
    const existing = await pool.query(
      `SELECT user_id FROM group_members WHERE group_id = $1 AND user_id = ANY($2::uuid[])`,
      [groupId, userIds],
    );
    const existingIds = new Set(existing.rows.map((r) => r.user_id));
    const toAdd = userIds.filter((id) => !existingIds.has(id));
    let added = 0;
    if (toAdd.length > 0) {
      const inserted = await pool.query(
        `INSERT INTO group_members (group_id, user_id)
         SELECT $1, x FROM unnest($2::uuid[]) AS x
         ON CONFLICT (group_id, user_id) DO NOTHING
         RETURNING user_id`,
        [groupId, toAdd],
      );
      added = inserted.rows.length;
    }
    res.json({ added });
  } catch (error) {
    next(error);
  }
});

app.get("/chat/groups/:groupId/messages", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    if (!(await isGroupMember(groupId, me))) {
      res.status(403).json({ error: "You are not a member of this group." });
      return;
    }
    const result = await pool.query(
      `SELECT m.*, u.full_name AS sender_name
       FROM group_messages m
       LEFT JOIN chat_users u ON u.user_id = m.sender_id
       WHERE m.group_id = $1
       ORDER BY m.created_at ASC
       LIMIT 500`,
      [groupId],
    );
    res.json({ messages: result.rows.map(groupMessageJson) });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups/:groupId/messages", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    const { text, isLocation, isVoice, voiceData, voiceMimeType, voiceDuration } =
      parseMessageBody(req.body || {});
    if (!(await isGroupMember(groupId, me))) {
      res.status(403).json({ error: "You are not a member of this group." });
      return;
    }
    if (!isVoice && !text) {
      res.status(400).json({ error: "Message text is required." });
      return;
    }
    if (isVoice && (!voiceData || voiceDuration < 1)) {
      res.status(400).json({ error: "Voice message data is required." });
      return;
    }
    const contentType = isVoice ? "voice" : isLocation ? "location" : "text";
    const result = await pool.query(
      `INSERT INTO group_messages (
         group_id, sender_id, content_type, text,
         voice_data, voice_mime_type, voice_duration
       ) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [groupId, me, contentType, isVoice ? "Voice message" : text, voiceData, voiceMimeType, voiceDuration],
    );
    res.status(201).json({
      message: groupMessageJson({
        ...result.rows[0],
        sender_name: clean(req.user.fullName) || "Member",
      }),
    });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups/:groupId/read", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    await pool.query(
      `UPDATE group_members SET last_read_at = now()
       WHERE group_id = $1 AND user_id = $2`,
      [groupId, me],
    );
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups/:groupId/leave", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    if (!(await isGroupMember(groupId, me))) {
      res.status(403).json({ error: "You are not a member of this group." });
      return;
    }
    await pool.query(
      `DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, me],
    );
    const remaining = await pool.query(
      `SELECT count(*)::int AS cnt FROM group_members WHERE group_id = $1`,
      [groupId],
    );
    if (remaining.rows[0].cnt === 0) {
      await pool.query(`DELETE FROM group_chats WHERE id = $1`, [groupId]);
    }
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.post("/chat/groups/:groupId/disband", requireAuth, async (req, res, next) => {
  try {
    const me = req.user.id;
    const groupId = clean(req.params.groupId);
    const group = await pool.query(
      `SELECT id, created_by FROM group_chats WHERE id = $1 LIMIT 1`,
      [groupId],
    );
    if (group.rows.length === 0) {
      res.status(404).json({ error: "Group not found." });
      return;
    }
    if (group.rows[0].created_by !== me) {
      res.status(403).json({ error: "Only the group creator can disband the group." });
      return;
    }
    await pool.query(`DELETE FROM group_chats WHERE id = $1`, [groupId]);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: "Server error. Please try again." });
});

app.listen(port, process.env.HOST || "0.0.0.0", () => {
  console.log(`Global Village chat API listening on port ${port}`);
});
