"use strict";

// Live comment/vote/notification/presence push bridge — the WebSocket/STOMP replacement for
// cbwire's own realtime.js (see .claude/plans/typed-seeking-frog.md, Phase 6). Subscribes to this
// page's destination(s) on connect and, on message, patches just the affected DOM via a small
// REST fetch — no SPA navigation exists in this app (every route is a full page load), so unlike
// the source app's realtime.js there is no wire:navigate resync. There IS a resync on a STOMP
// *reconnect* though (see onConnect below) — a dropped connection can miss broadcasts a
// wire:navigate-style resync would otherwise never need to worry about.
(function () {
	if (!window.WebSocket || !window.StompJs) return;

	const ctx = window.dismal || {};
	const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";

	// Set once the FIRST onConnect has run, so a later reconnect (server restart, network blip —
	// StompJs's own reconnectDelay handles retrying the connection itself) is distinguishable from
	// the initial one below.
	let hasConnectedBefore = false;

	const client = new window.StompJs.Client({
		brokerURL: protocol + "//" + window.location.host + "/stomp",
		reconnectDelay: 5000,
		heartbeatIncoming: 10000,
		heartbeatOutgoing: 10000,
		onConnect: function () {
			if (ctx.post_id_short) {
				client.subscribe("post." + ctx.post_id_short, handlePostMessage);
				sendPostPresencePing();
			}
			// Anonymous visitors share the default user's uid, which the server always denies a
			// user.* subscription to — and STOMP closes the WHOLE connection on any denial, not
			// just that one subscription. Only subscribe when actually identified.
			if (ctx.is_identified && ctx.uid) {
				client.subscribe("user." + ctx.uid, handleUserMessage);
			}
			if (ctx.forum_id_short) {
				client.subscribe("forum." + ctx.forum_id_short, handleForumMessage);
				sendPresencePing();
			}
			// A reconnect re-subscribes to everything above, but any comment-added/vote-changed
			// broadcasts that happened during the gap were never received — nothing else would
			// ever re-fetch them since every route here is a full page load, not a SPA with its
			// own resync-on-navigate. Skipped on the very first connect (right after a full page
			// render, so there's nothing missed yet) to avoid a redundant fetch of data the page
			// already has.
			if (hasConnectedBefore) {
				refreshComments();
				refreshPostVote();
			}
			hasConnectedBefore = true;
		}
	});

	function parseBody(message) {
		try {
			return JSON.parse(message.body);
		} catch (e) {
			return null;
		}
	}

	async function refreshComments() {
		if (!ctx.post_id_short) return;
		try {
			const res = await fetch(`/posts/${ctx.post_id_short}/comments-html`);
			if (!res.ok) return;
			const html = await res.text();
			const root = document.querySelector("[data-comments-root]");
			if (root) root.innerHTML = html;
		} catch (e) { /* best-effort */ }
	}

	async function refreshPostVote() {
		if (!ctx.post_id_short) return;
		try {
			const res = await fetch(`/posts/${ctx.post_id_short}/vote-score`);
			if (!res.ok) return;
			const body = await res.json();
			const scope = document.querySelector(`[data-post-id="${CSS.escape(ctx.post_id_short)}"]`);
			if (!scope) return;
			const scoreEl = scope.querySelector("[data-vote-score]");
			if (scoreEl) scoreEl.textContent = body.data.score;
		} catch (e) { /* best-effort */ }
	}

	function handlePostMessage(message) {
		const body = parseBody(message);
		if (!body || !body.event) return;
		if (body.event === "comment-added" || body.event === "comment-vote-changed") {
			refreshComments();
		} else if (body.event === "post-vote-changed") {
			refreshPostVote();
		} else if (body.event === "post-presence") {
			const el = document.querySelector("[data-post-presence-count]");
			if (el) el.textContent = body.count + " viewing now";
		}
	}

	function handleUserMessage(message) {
		const body = parseBody(message);
		if (!body || body.event !== "notification-received") return;
		if (typeof DTActions !== "undefined") DTActions.bumpNotificationBadge();
	}

	function handleForumMessage(message) {
		const body = parseBody(message);
		if (!body || body.event !== "forum-presence") return;
		const el = document.querySelector("[data-forum-presence-count]");
		if (el) el.textContent = body.count + " viewing now";
	}

	// Sent as a STOMP SEND on the same post./forum. destination the page already subscribes to for
	// broadcasts — the server absorbs it (ws/Stomp.bx's onSend()) and pushes back a computed
	// count, never relaying the raw ping itself. Guarded by client.connected since the periodic
	// setInterval below keeps firing across reconnects/disconnects; publish() throws if called
	// while not connected, and a missed heartbeat is harmless (presence has its own TTL).
	function sendPresencePing() {
		if (!ctx.forum_id_short || !client.connected) return;
		try {
			client.publish({ destination: "forum." + ctx.forum_id_short, body: "" });
		} catch (e) { /* best-effort */ }
	}

	function sendPostPresencePing() {
		if (!ctx.post_id_short || !client.connected) return;
		try {
			client.publish({ destination: "post." + ctx.post_id_short, body: "" });
		} catch (e) { /* best-effort */ }
	}

	setInterval(sendPresencePing, 30000);
	setInterval(sendPostPresencePing, 30000);

	client.activate();
})();
