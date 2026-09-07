"use strict";

// Fetch-based replacement for the source app's cbwire `wire:click` mutations — every button/form
// below hits one of routes/ActionsRouter.bx's endpoints and patches just the affected DOM, no
// page reload. Event delegation on `document` so this works for comment nodes inserted later
// (replies) without re-binding anything.

const DTActions = (function () {

	// The CSRF token minted by boxExpressCsrf() for this page load (see lib/RequestContext.bx /
	// views/layouts/Main.bxm's <meta name="csrf-token">). GET/HEAD/OPTIONS requests are exempt
	// server-side, so only state-changing fetches below need it, via this header.
	function csrfToken() {
		const meta = document.querySelector('meta[name="csrf-token"]');
		return meta ? meta.getAttribute("content") : "";
	}

	async function postJSON(url, method, data) {
		const res = await fetch(url, {
			method: method,
			headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
			body: data === undefined ? undefined : JSON.stringify(data)
		});
		let body = null;
		try { body = await res.json(); } catch (e) { /* e.g. 204/empty */ }
		if (!res.ok) {
			const message = (body && body.error) || ("Request failed (" + res.status + ")");
			throw new Error(message);
		}
		return body ? body.data : null;
	}

	// The source app's ported CSS (comments.css etc.) sets `display: flex/block` directly on
	// several of these elements' classes, which beats the `[hidden]` UA-stylesheet rule on
	// specificity/source-order — so toggling the native `hidden` attribute silently does
	// nothing visually here. Inline style always wins; use that instead.
	function hide(el) { if (el) el.style.display = "none"; }
	function show(el) { if (el) el.style.display = ""; }
	function isHidden(el) { return !!el && el.style.display === "none"; }

	function requireLogin() {
		if (window.DTModal) window.DTModal.open("login-modal");
	}

	function isAuthRequired(err) {
		return /Authentication required/i.test(err.message);
	}

	// ── Votes (shared by post + comment vote buttons) ─────────────────────

	function applyVoteResult(scope, result) {
		const scoreEl = scope.querySelector("[data-vote-score]");
		if (scoreEl) scoreEl.textContent = result.score;
		const upBtn = scope.querySelector("[data-vote-up]");
		const downBtn = scope.querySelector("[data-vote-down]");
		if (upBtn) upBtn.classList.toggle("c-vote--active-up", result.userVote === 1);
		if (downBtn) downBtn.classList.toggle("c-vote--active-down", result.userVote === -1);
	}

	async function handleVoteClick(btn, value) {
		const postId = btn.dataset.postId;
		const commentId = btn.dataset.commentId;
		const url = postId ? `/posts/${postId}/vote` : `/comments/${commentId}/vote`;
		// The vote button itself also carries data-comment-id (so its own click handler can read
		// btn.dataset.commentId) — closest() run from the button would match the button itself,
		// not the ancestor scope, so start the search one level up instead.
		const scope = postId ? document.querySelector(`[data-post-id="${CSS.escape(postId)}"]`) : btn.parentElement.closest("[data-comment-id]");
		try {
			const result = await postJSON(url, "POST", { value: value });
			if (scope) applyVoteResult(scope, result);
		} catch (e) {
			if (isAuthRequired(e)) requireLogin();
			else DTGlobal.toast(e.message, "error");
		}
	}

	// ── Bookmark ───────────────────────────────────────────────────────────

	async function handleBookmarkClick(btn) {
		const postId = btn.dataset.postId;
		try {
			const result = await postJSON(`/posts/${postId}/bookmark`, "POST");
			btn.classList.toggle("c-post__bookmark--active", result.bookmarked);
			btn.setAttribute("aria-label", result.bookmarked ? "Remove bookmark" : "Bookmark");
			const icon = btn.querySelector("i");
			if (icon) icon.className = "bi " + (result.bookmarked ? "bi-bookmark-fill" : "bi-bookmark");
		} catch (e) {
			if (isAuthRequired(e)) requireLogin();
			else DTGlobal.toast(e.message, "error");
		}
	}

	// ── Post edit / delete / pin ────────────────────────────────────────────

	function handlePostEditToggle(btn) {
		const article = btn.closest("[data-post-id]");
		const form = article.querySelector("[data-post-edit-form]");
		const body = article.querySelector("[data-post-body]");
		if (!form) return;
		if (!isHidden(form)) {
			hide(form);
			show(body);
		} else {
			show(form);
			hide(body);
		}
	}

	async function handlePostEditSubmit(form) {
		const article = form.closest("[data-post-id]");
		const postId = article.dataset.postId;
		const textarea = form.querySelector("textarea");
		try {
			const result = await postJSON(`/posts/${postId}`, "PUT", { body: textarea.value });
			const body = article.querySelector("[data-post-body]");
			if (body) {
				body.innerHTML = result.bodyHtml;
				show(body);
			}
			hide(form);
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	async function handlePostDelete(btn) {
		if (!window.confirm("Delete this post?")) return;
		const postId = btn.dataset.postId;
		try {
			await postJSON(`/posts/${postId}`, "DELETE");
			window.location.href = "/f/all";
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	async function handlePostPinToggle(btn) {
		const postId = btn.dataset.postId;
		try {
			const result = await postJSON(`/posts/${postId}/pin`, "POST");
			btn.textContent = result.pinned ? "Unpin" : "Pin";
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	// ── Comments: add / reply / edit / delete ───────────────────────────────

	async function handleCommentFormSubmit(form) {
		const postId = document.querySelector("[data-post-id]").dataset.postId;
		const parentId = form.dataset.parentId || "";
		const textarea = form.querySelector("textarea");
		const body = textarea.value.trim();
		if (!body) return;

		try {
			const res = await fetch(`/posts/${postId}/comments`, {
				method: "POST",
				headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
				body: JSON.stringify({ body: body, parent_id: parentId })
			});
			const html = await res.text();
			if (!res.ok) {
				let message = "Failed to post comment";
				try { message = JSON.parse(html).error || message; } catch (e) {}
				throw new Error(message);
			}

			if (parentId) {
				// Reply: insert into the parent's children container, then hide the reply form.
				const parentNode = document.getElementById("c-" + parentId);
				const childrenEl = parentNode && parentNode.querySelector(":scope > [data-comment-children]");
				if (childrenEl) childrenEl.insertAdjacentHTML("beforeend", html);
				hide(form);
			} else {
				const root = document.querySelector("[data-comments-root]");
				const noComments = root.querySelector("[data-no-comments]");
				if (noComments) noComments.remove();
				root.insertAdjacentHTML("beforeend", html);
			}
			textarea.value = "";
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	function handleReplyToggle(btn) {
		const node = document.getElementById("c-" + btn.dataset.commentId);
		const form = node && node.querySelector(":scope > [data-reply-form]");
		if (!form) return;
		isHidden(form) ? show(form) : hide(form);
	}

	function handleEditToggle(btn) {
		const node = document.getElementById("c-" + btn.dataset.commentId);
		if (!node) return;
		let form = node.querySelector(":scope > [data-comment-edit-form]");
		const body = node.querySelector(":scope > [data-comment-body]");
		if (!form) {
			form = document.createElement("form");
			form.className = "c-comment__edit-form";
			form.setAttribute("data-comment-edit-form", "");
			form.dataset.commentId = btn.dataset.commentId;
			const ta = document.createElement("textarea");
			ta.className = "c-comment__textarea";
			ta.rows = 3;
			ta.value = body ? body.textContent.trim() : "";
			const actions = document.createElement("div");
			actions.className = "c-comment__actions";
			const saveBtn = document.createElement("button");
			saveBtn.type = "submit";
			saveBtn.className = "c-comment__pill c-comment__button";
			saveBtn.textContent = "Save";
			actions.append(saveBtn);
			form.append(ta, actions);
			body.insertAdjacentElement("afterend", form);
			hide(form);
		}
		isHidden(form) ? show(form) : hide(form);
	}

	async function handleCommentEditSubmit(form) {
		const commentId = form.dataset.commentId;
		const textarea = form.querySelector("textarea");
		try {
			const result = await postJSON(`/comments/${commentId}`, "PUT", { body: textarea.value });
			const node = document.getElementById("c-" + commentId);
			const body = node && node.querySelector(":scope > [data-comment-body]");
			if (body) body.innerHTML = result.bodyHtml;
			hide(form);
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	async function handleCommentDelete(btn) {
		if (!window.confirm("Delete this comment?")) return;
		const commentId = btn.dataset.commentId;
		try {
			await postJSON(`/comments/${commentId}`, "DELETE");
			const node = document.getElementById("c-" + commentId);
			if (node) {
				const body = node.querySelector(":scope > [data-comment-body]");
				if (body) body.textContent = "[deleted]";
				const actions = node.querySelector(":scope > .c-comment__actions");
				if (actions) actions.remove();
			}
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	// ── Forum subscribe ──────────────────────────────────────────────────────

	async function handleSubscribeToggle(btn) {
		const forum = btn.dataset.forum;
		try {
			const result = await postJSON(`/forums/${forum}/subscribe`, "POST");
			// A forum page can carry two of these at once — a mobile-only one in the header strip
			// and a desktop-only one in the sidebar (views/widgets/forum_details.bxm) — both need
			// to reflect the new state, not just whichever one was actually clicked.
			document.querySelectorAll(`[data-subscribe-toggle][data-forum="${CSS.escape(forum)}"]`).forEach((el) => {
				el.textContent = result.subscribed ? "Unsubscribe" : "Subscribe";
				el.classList.toggle("c-forum__cta--subscribed", result.subscribed);
			});
		} catch (e) {
			if (isAuthRequired(e)) requireLogin();
			else DTGlobal.toast(e.message, "error");
		}
	}

	// ── Forum moderation: details / privacy / moderators / members ──────────

	function forumDisplay() {
		const root = document.querySelector("[data-forum-mod]");
		return root ? root.dataset.forumDisplay : null;
	}

	function renderUserRow(username, removeAttr) {
		const tr = document.createElement("tr");
		const tdName = document.createElement("td");
		const a = document.createElement("a");
		a.href = `/u/${encodeURIComponent(username)}`;
		a.className = "post-link text-decoration-none";
		a.textContent = username;
		tdName.appendChild(a);
		const tdBtn = document.createElement("td");
		const btn = document.createElement("button");
		btn.type = "button";
		btn.className = "btn btn-sm btn-outline-danger";
		btn.setAttribute(removeAttr, "");
		btn.dataset.username = username;
		btn.textContent = "Remove";
		tdBtn.appendChild(btn);
		tr.append(tdName, tdBtn);
		return tr;
	}

	function renderList(tbody, list, noRowAttr, removeAttr, emptyLabel) {
		tbody.innerHTML = "";
		if (!list.length) {
			const tr = document.createElement("tr");
			tr.setAttribute(noRowAttr, "");
			const td = document.createElement("td");
			td.colSpan = 2;
			td.className = "mod-table__muted";
			td.textContent = emptyLabel;
			tr.appendChild(td);
			tbody.appendChild(tr);
			return;
		}
		list.forEach((row) => tbody.appendChild(renderUserRow(row.user_name, removeAttr)));
	}

	async function handleForumDetailsSubmit(form) {
		const forum = forumDisplay();
		const statusEl = form.querySelector("[data-forum-save-status]") || document.querySelector("[data-forum-save-status]");
		try {
			await postJSON(`/forums/${encodeURIComponent(forum)}`, "PUT", {
				about: form.querySelector('[name="about"]').value,
				icon: form.querySelector('[name="icon"]').value
			});
			if (statusEl) { statusEl.textContent = "Changes saved."; statusEl.className = "text-success mb-2"; }
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	async function handleForumPrivacyToggle(btn) {
		const forum = forumDisplay();
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/privacy-toggle`, "POST");
			btn.textContent = result.isPrivate ? "Private — Make Public" : "Public — Make Private";
			btn.className = "btn " + (result.isPrivate ? "btn-warning" : "btn-outline-secondary");
			btn.dataset.isPrivate = result.isPrivate ? "1" : "0";
			const text = document.querySelector("[data-forum-privacy-text]");
			if (text) text.innerHTML = result.isPrivate
				? "This forum is <strong>private</strong> &mdash; hidden from the sidebar and feeds for non-members."
				: "This forum is <strong>public</strong> &mdash; visible to everyone.";
			const membersSection = document.querySelector("[data-members-section]");
			if (membersSection) membersSection.style.display = result.isPrivate ? "" : "none";
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	async function handleAddModerator(form) {
		const forum = forumDisplay();
		const input = form.querySelector('[name="username"]');
		const statusEl = document.querySelector("[data-mod-status]");
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/moderators`, "POST", { username: input.value });
			renderList(document.querySelector("[data-mods-tbody]"), result.mods, "data-no-mods-row", "data-remove-moderator", "No moderators yet.");
			input.value = "";
			if (statusEl) { statusEl.textContent = ""; }
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	async function handleRemoveModerator(btn) {
		const forum = forumDisplay();
		const statusEl = document.querySelector("[data-mod-status]");
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/moderators/${encodeURIComponent(btn.dataset.username)}`, "DELETE");
			renderList(document.querySelector("[data-mods-tbody]"), result.mods, "data-no-mods-row", "data-remove-moderator", "No moderators yet.");
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	// ── Moderator dashboard: forum-select-driven moderator management ─────

	function dashSelectedForum() {
		const select = document.querySelector("[data-mods-forum-select]");
		return select ? select.value : "";
	}

	async function handleModsForumSelectChange(select) {
		const forum = select.value;
		const addForm = document.querySelector("[data-add-mod-form]");
		const table = document.querySelector("[data-mods-table]");
		const statusEl = document.querySelector("[data-mod-status]");
		if (statusEl) statusEl.textContent = "";
		if (!forum) { hide(addForm); hide(table); return; }
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/moderators`, "GET");
			show(addForm);
			show(table);
			renderList(document.querySelector("[data-dash-mods-tbody]"), result.mods, "data-no-mods-row", "data-dash-remove-moderator", "No moderators yet.");
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	async function handleDashAddModerator(form) {
		const forum = dashSelectedForum();
		const input = form.querySelector('[name="username"]');
		const statusEl = document.querySelector("[data-mod-status]");
		if (!forum) return;
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/moderators`, "POST", { username: input.value });
			renderList(document.querySelector("[data-dash-mods-tbody]"), result.mods, "data-no-mods-row", "data-dash-remove-moderator", "No moderators yet.");
			input.value = "";
			if (statusEl) statusEl.textContent = "";
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	async function handleDashRemoveModerator(btn) {
		const forum = dashSelectedForum();
		const statusEl = document.querySelector("[data-mod-status]");
		if (!forum) return;
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/moderators/${encodeURIComponent(btn.dataset.username)}`, "DELETE");
			renderList(document.querySelector("[data-dash-mods-tbody]"), result.mods, "data-no-mods-row", "data-dash-remove-moderator", "No moderators yet.");
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	// ── Moderator dashboard: create forum ──────────────────────────────────

	async function handleCreateForumSubmit(form) {
		const display = form.querySelector('[name="display"]');
		const about = form.querySelector('[name="about"]');
		const alertEl = document.querySelector("#mod-forums-alert");
		try {
			await postJSON("/forums", "POST", { display: display.value, about: about.value });
			window.location.reload();
		} catch (e) {
			if (alertEl) alertEl.innerHTML = `<div class="mod-alert mod-alert--error">${e.message}</div>`;
		}
	}

	async function handleAddMember(form) {
		const forum = forumDisplay();
		const input = form.querySelector('[name="username"]');
		const statusEl = document.querySelector("[data-member-status]");
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/members`, "POST", { username: input.value });
			renderList(document.querySelector("[data-members-tbody]"), result.members, "data-no-members-row", "data-remove-member", "No members yet.");
			input.value = "";
			if (statusEl) { statusEl.textContent = ""; }
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	async function handleRemoveMember(btn) {
		const forum = forumDisplay();
		const statusEl = document.querySelector("[data-member-status]");
		try {
			const result = await postJSON(`/forums/${encodeURIComponent(forum)}/members/${encodeURIComponent(btn.dataset.username)}`, "DELETE");
			renderList(document.querySelector("[data-members-tbody]"), result.members, "data-no-members-row", "data-remove-member", "No members yet.");
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger mb-2"; }
		}
	}

	// ── Mobile forum drawer ────────────────────────────────────────────────

	function openMobileNav() {
		const drawer = document.querySelector("[data-mobile-nav-drawer]");
		const backdrop = document.querySelector("[data-mobile-nav-backdrop]");
		const toggle = document.querySelector("[data-mobile-nav-toggle]");
		if (!drawer || !backdrop) return;
		show(drawer);
		show(backdrop);
		// Toggling the transform that actually slides the drawer in has to happen on the next
		// frame, after `display:none` is lifted — flipping both in the same tick means the
		// browser never renders the "closed" (translateX(-100%)) state to transition from.
		requestAnimationFrame(() => drawer.setAttribute("data-open", ""));
		if (toggle) toggle.setAttribute("aria-expanded", "true");
	}

	function closeMobileNav() {
		const drawer = document.querySelector("[data-mobile-nav-drawer]");
		const backdrop = document.querySelector("[data-mobile-nav-backdrop]");
		const toggle = document.querySelector("[data-mobile-nav-toggle]");
		if (!drawer || !backdrop) return;
		drawer.removeAttribute("data-open");
		if (toggle) toggle.setAttribute("aria-expanded", "false");
		// Wait for the slide-out transition to finish before removing it from layout, or it just
		// vanishes instantly instead of sliding away.
		setTimeout(() => { hide(drawer); hide(backdrop); }, 200);
	}

	// ── User menu dropdown ──────────────────────────────────────────────────

	function handleUsermenuToggle(btn) {
		const widget = btn.closest("[data-usermenu-widget]");
		const dropdown = widget.querySelector("[data-usermenu-dropdown]");
		const nowOpen = isHidden(dropdown);
		isHidden(dropdown) ? show(dropdown) : hide(dropdown);
		btn.setAttribute("aria-expanded", nowOpen ? "true" : "false");
	}

	async function handleLogout() {
		try {
			await fetch("/logout", { method: "POST", headers: { "X-CSRF-Token": csrfToken() } });
		} catch (e) { /* best-effort */ }
		window.location.href = "/";
	}

	// ── Notifications bell ────────────────────────────────────────────────────

	function notifItemClass(notif) {
		return "header-notif__item" + (notif.is_read == 0 ? " header-notif__item--unread" : "");
	}

	// "achievement_unlocked" is a legacy type value from old seed data — AchievementService.bx
	// only ever writes "achievement" now, but old rows can still carry the stale name.
	function isAchievementNotif(notif) {
		return notif.type === "achievement" || notif.type === "achievement_unlocked";
	}

	function notifBody(notif) {
		if (isAchievementNotif(notif)) {
			return `<div><i class="bi bi-trophy-fill header-notif__trophy" aria-hidden="true"></i> <span class="header-notif__achievement-title">${escapeHtml(notif.achievement_title || "")}</span></div>`;
		}
		let verb = "replied to your comment on";
		if (notif.type === "comment_on_post") verb = "commented on your post";
		else if (notif.type === "upvote_post") verb = notif.upvote_count != null ? `your post has been upvoted ${escapeHtml(String(notif.upvote_count))} times` : "upvoted your post";
		return `<div><span class="header-notif__actor">${escapeHtml(notif.actor_name || "")}</span> ${verb} <span class="header-notif__post">${escapeHtml(notif.post_title || "")}</span></div>`;
	}

	function escapeHtml(str) {
		const div = document.createElement("div");
		div.textContent = str;
		return div.innerHTML;
	}

	function notifHref(notif) {
		if (isAchievementNotif(notif)) {
			// Reuse the profile link already in the header rather than threading the current
			// username through window.dismal just for this — the usermenu's "Profile" link is
			// exactly /u/<username>.
			const profileHref = document.querySelector('[data-usermenu-widget] a[href^="/u/"]')?.getAttribute("href");
			return profileHref ? `${profileHref}/achievements` : null;
		}
		return `/f/${encodeURIComponent(notif.forum_display)}/comments/${encodeURIComponent(notif.post_id_short)}/${encodeURIComponent((notif.post_title || "").toLowerCase().replace(/[^a-z0-9]+/g, "-"))}`;
	}

	async function handleNotificationsToggle(btn) {
		const widget = btn.closest("[data-notifications-widget]");
		const dropdown = widget.querySelector("[data-notifications-dropdown]");
		if (!isHidden(dropdown)) { hide(dropdown); return; }

		try {
			const result = await postJSON("/notifications/recent", "GET");
			const list = widget.querySelector("[data-notifications-list]");
			if (!result.notifications.length) {
				list.innerHTML = '<div class="header-notif__empty" style="padding:12px;">No notifications yet</div>';
			} else {
				list.innerHTML = result.notifications.map((n) => {
					const href = notifHref(n);
					const inner = notifBody(n);
					return href
						? `<a href="${href}" class="${notifItemClass(n)}" style="display:block; padding:8px 12px; text-decoration:none;">${inner}</a>`
						: `<div class="${notifItemClass(n)}" style="padding:8px 12px;">${inner}</div>`;
				}).join("");
			}
			show(dropdown);

			const badge = widget.querySelector("[data-notification-badge]");
			if (badge) hide(badge);
			await postJSON("/notifications/mark-read", "POST");
		} catch (e) {
			DTGlobal.toast(e.message, "error");
		}
	}

	function bumpNotificationBadge() {
		const badge = document.querySelector("[data-notification-badge]");
		if (!badge) return;
		const current = parseInt(badge.textContent, 10) || 0;
		badge.textContent = String(current + 1);
		show(badge);
	}

	// ── Post editor: link/post tab toggle + async link-preview fetch ────────

	function handleEditorTabClick(btn) {
		const form = btn.closest("[data-editor-form]");
		if (!form) return;
		const type = btn.dataset.postType;

		form.querySelectorAll("[data-post-type-tab]").forEach((t) => {
			t.classList.toggle("editor-tab--active", t === btn);
		});
		const hiddenInput = form.querySelector("[data-post-type-input]");
		if (hiddenInput) hiddenInput.value = type;

		const linkField = form.querySelector("[data-editor-link-field]");
		const bodyField = form.querySelector("[data-editor-body-field]");
		if (type === "link") {
			show(linkField);
		} else {
			hide(linkField);
		}
		show(bodyField);
	}

	async function handleEditorLinkBlur(input) {
		const form = input.closest("[data-editor-form]");
		const statusEl = form.querySelector("[data-link-preview-status]");
		const titleInput = form.querySelector("#editor_title");
		const previewCard = form.querySelector("[data-link-preview-card]");
		const url = input.value.trim();
		if (!url) { if (previewCard) hide(previewCard); return; }
		if (statusEl) statusEl.textContent = "Loading preview…";
		if (previewCard) hide(previewCard);
		const requestToken = (input._linkPreviewToken = (input._linkPreviewToken || 0) + 1);
		try {
			const res = await fetch(`/submit/link-preview?url=${encodeURIComponent(url)}`);
			const result = await res.json();
			if (input._linkPreviewToken !== requestToken) return; // a newer blur superseded this request
			if (result.success) {
				if (statusEl) statusEl.textContent = "Metadata loaded successfully";
				if (titleInput && !titleInput.value.trim() && result.title) titleInput.value = result.title;
				if (previewCard) renderLinkPreviewCard(previewCard, url, result);
			} else if (statusEl) {
				statusEl.textContent = result.error || "No metadata found for this URL";
			}
		} catch (e) {
			if (statusEl) statusEl.textContent = "";
		}
	}

	function renderLinkPreviewCard(card, url, result) {
		let domain = url;
		try {
			domain = new URL(url).hostname.replace(/^www\./, "");
		} catch (e) { /* keep raw url as fallback */ }

		const titleEl = card.querySelector("[data-link-preview-title]");
		if (titleEl) titleEl.textContent = result.title || domain;

		const domainEl = card.querySelector("[data-link-preview-domain]");
		if (domainEl) domainEl.textContent = domain;

		const descEl = card.querySelector("[data-link-preview-desc]");
		if (descEl) {
			if (result.description) { descEl.textContent = result.description; show(descEl); }
			else { descEl.textContent = ""; hide(descEl); }
		}

		const thumbLink = card.querySelector("[data-link-preview-thumb-link]");
		const thumbImg = card.querySelector("[data-link-preview-thumb-img]");
		if (thumbLink && thumbImg) {
			if (result.image) {
				thumbImg.src = result.image;
				thumbLink.href = url;
				show(thumbLink);
			} else {
				thumbImg.removeAttribute("src");
				hide(thumbLink);
			}
		}

		show(card);
	}

	// ── Settings: password change ────────────────────────────────────────────

	async function handlePasswordFormSubmit(form) {
		const current = form.querySelector('[name="current_password"]').value;
		const next = form.querySelector('[name="new_password"]').value;
		const confirmEl = form.querySelector('[name="confirm_password"]');
		const statusEl = form.querySelector("[data-settings-status]");
		if (confirmEl && confirmEl.value !== next) {
			if (statusEl) { statusEl.textContent = "New password and confirmation don't match."; statusEl.className = "text-danger"; }
			return;
		}
		try {
			await postJSON("/settings/password", "POST", { current_password: current, new_password: next });
			if (statusEl) { statusEl.textContent = "Password updated."; statusEl.className = "text-success"; }
			form.reset();
		} catch (e) {
			if (statusEl) { statusEl.textContent = e.message; statusEl.className = "text-danger"; }
		}
	}

	// ── Achievements: grid ↔ detail view (all data pre-rendered, client-only) ─

	function escapeHtml(str) {
		const div = document.createElement("div");
		div.textContent = str === undefined || str === null ? "" : String(str);
		return div.innerHTML;
	}

	function achData() {
		const el = document.getElementById("ach-data");
		if (!el) return null;
		if (!achData._cache) {
			try { achData._cache = JSON.parse(el.textContent); } catch (e) { return null; }
		}
		return achData._cache;
	}

	function buildAchievementDetail(slug, tierNum) {
		const d = achData();
		if (!d) return "";
		const ach = d.achievements.find((a) => a.slug === slug);
		if (!ach) return "";
		const icon = d.iconMap[ach.metric] || "★";
		const allTiers = d.allTierMap[slug] || [];
		const tier = tierNum || ach.current_tier;
		const selTierData = allTiers.find((t) => +t.tier === +tier) || {};
		const hexOf = (i) => "#" + d.tierHex[i - 1];

		let tiersHtml = "";
		allTiers.forEach((t) => {
			const tIdx = +t.tier;
			if (tIdx > ach.current_tier) return;
			const isActive = tIdx === +tier;
			const h = hexOf(tIdx);
			const rgb = d.tierRgb[tIdx - 1];
			const activeStyle = isActive ? `border-color:${h};background:rgba(${rgb},0.12);color:#fafaf9;` : "";
			tiersHtml += `<button type="button" class="c-ach-tier-btn ${isActive ? "c-ach-tier-btn--active" : ""}" style="--tier-color:${h};--tier-color-rgb:${rgb};${activeStyle}" data-ach-tier-btn data-slug="${escapeHtml(slug)}" data-tier="${tIdx}">
				<span class="c-ach-tier-btn__rarity" ${isActive ? `style="color:${h}"` : ""}>${escapeHtml(d.tierRarity[tIdx - 1])}</span>
				<span>${escapeHtml(t.label)}</span>
			</button>`;
		});

		let displayHtml = "";
		if (selTierData && selTierData.tier) {
			const h = hexOf(tier);
			const rgb = d.tierRgb[tier - 1];
			displayHtml = `
				<div class="c-ach-display" style="--tier-color:${h};--tier-color-rgb:${rgb};">
					<div class="c-ach-display__corner c-ach-display__corner--tl"></div>
					<div class="c-ach-display__corner c-ach-display__corner--tr"></div>
					<div class="c-ach-display__corner c-ach-display__corner--bl"></div>
					<div class="c-ach-display__corner c-ach-display__corner--br"></div>
					<div class="c-ach-display__header">
						<div class="c-ach-display__icon">${icon}</div>
						<div class="c-ach-display__info">
							<div class="c-ach-display__badges">
								<span class="c-ach-display__tier-badge">Tier ${escapeHtml(d.tierRoman[tier - 1])} — ${escapeHtml(d.tierRarity[tier - 1])}</span>
								<span class="c-ach-display__threshold">${escapeHtml(selTierData.threshold)}</span>
							</div>
							<div class="c-ach-display__label">${escapeHtml(selTierData.label)}</div>
							<h2 class="c-ach-display__title">${escapeHtml(selTierData.title)}</h2>
						</div>
					</div>
					<hr class="c-ach-display__divider">
					<div class="c-ach-display__flavor-section">
						<div class="c-ach-display__flavor-label">System Notation</div>
						<p class="c-ach-display__flavor">"${escapeHtml(selTierData.flavor)}"</p>
					</div>
				</div>`;
		}

		let stripHtml = "";
		allTiers.forEach((t) => {
			const tIdx = +t.tier;
			const isEarned = tIdx <= ach.current_tier;
			const clickable = isEarned ? `data-ach-tier-btn data-slug="${escapeHtml(slug)}" data-tier="${tIdx}" style="cursor:pointer;"` : "";
			stripHtml += `<div class="c-ach-strip__pip c-tier-pip--${tIdx} ${tIdx === +tier ? "c-ach-strip__pip--active" : "c-ach-strip__pip--dim"} ${!isEarned ? "c-ach-strip__pip--locked" : ""}" ${clickable}></div>`;
		});

		return `
			<a href="#" class="c-ach-detail__back" data-ach-back>← Back to Registry</a>
			<div class="c-ach-detail__heading">${icon} ${escapeHtml(ach.category)}</div>
			<div class="c-ach-tiers">${tiersHtml}</div>
			${displayHtml}
			<div class="c-ach-strip">${stripHtml}</div>
			<div class="c-ach-strip__labels"><span class="c-ach-strip__label">Common</span><span class="c-ach-strip__label">Legendary</span></div>
		`;
	}

	function showAchievementDetail(slug, tierNum) {
		const grid = document.querySelector("[data-ach-grid]");
		const detail = document.querySelector("[data-ach-detail]");
		if (!grid || !detail) return;
		detail.innerHTML = buildAchievementDetail(slug, tierNum);
		hide(grid);
		show(detail);
	}

	function showAchievementGrid() {
		const grid = document.querySelector("[data-ach-grid]");
		const detail = document.querySelector("[data-ach-detail]");
		if (!grid || !detail) return;
		show(grid);
		hide(detail);
		detail.innerHTML = "";
	}

	// ── Infinite scroll (feed pages) ──────────────────────────────────────────
	// The source app scaffolded this (a Feed bean with cursor pagination, a `.feed-sentinel`
	// marker div, a loadMore() wire action) but never actually wired a client-side trigger to
	// it anywhere — no IntersectionObserver, no wire:intersect, checked its own assets/js and
	// built dist/ bundles. This is the piece that was always missing.

	function initInfiniteScroll() {
		const sentinel = document.querySelector("[data-feed-sentinel]");
		const list = document.querySelector("[data-feed-list]");
		if (!sentinel || !list) return;

		const loader = document.querySelector("[data-feed-loader]");
		const endEl = document.querySelector("[data-feed-end]");
		let loading = false;

		const observer = new IntersectionObserver((entries) => {
			if (entries[0].isIntersecting) loadMore();
		}, { rootMargin: "600px 0px" });

		const mode = sentinel.dataset.feedMode || "cursor";

		async function fetchNextBatch() {
			if (mode === "offset") {
				const offset = +sentinel.dataset.feedOffset || 0;
				const base = sentinel.dataset.feedEndpoint;
				const sep = base.includes("?") ? "&" : "?";
				return fetch(`${base}${sep}offset=${offset}`);
			}
			const forum = sentinel.dataset.feedForum || "all";
			const before = sentinel.dataset.feedBefore;
			return fetch(`/feed/more?forum=${encodeURIComponent(forum)}&before=${encodeURIComponent(before)}`);
		}

		async function loadMore() {
			if (loading) return;
			loading = true;
			if (loader) show(loader);
			try {
				const res = await fetchNextBatch();
				const hasMore = res.headers.get("X-Feed-Has-More") === "true";
				const html = await res.text();
				if (html.trim()) {
					list.insertAdjacentHTML("beforeend", html);
					if (window.DTGlobal && typeof DTGlobal.initYoutubeEmbeds === "function") DTGlobal.initYoutubeEmbeds();
					if (window.DTGlobal && typeof DTGlobal.initTwitchEmbeds === "function") DTGlobal.initTwitchEmbeds();
					if (mode === "offset") {
						const added = (html.match(/<article /g) || []).length;
						sentinel.dataset.feedOffset = (+sentinel.dataset.feedOffset || 0) + added;
					} else {
						const cards = list.querySelectorAll("[data-post-id]");
						const lastTs = cards[cards.length - 1]?.querySelector("[data-ts]");
						if (lastTs) sentinel.dataset.feedBefore = lastTs.dataset.ts;
					}
				}
				if (!hasMore) {
					observer.disconnect();
					sentinel.remove();
					if (endEl) show(endEl);
				}
			} catch (e) {
				// best-effort — leave the sentinel in place so the next scroll/intersection retries
			} finally {
				loading = false;
				if (loader) hide(loader);
			}
		}

		observer.observe(sentinel);
	}

	function init() {
		initInfiniteScroll();

		document.addEventListener("keydown", (e) => {
			if (e.key !== "Escape") return;
			const drawer = document.querySelector("[data-mobile-nav-drawer]");
			if (drawer && drawer.hasAttribute("data-open")) closeMobileNav();
		});

		document.addEventListener("click", (e) => {
			const voteUp = e.target.closest("[data-vote-up]");
			const voteDown = e.target.closest("[data-vote-down]");
			if (voteUp) { handleVoteClick(voteUp, 1); return; }
			if (voteDown) { handleVoteClick(voteDown, -1); return; }

			const bookmarkBtn = e.target.closest("[data-bookmark-toggle]");
			if (bookmarkBtn) { handleBookmarkClick(bookmarkBtn); return; }

			const postEditToggle = e.target.closest("[data-post-edit-toggle]");
			if (postEditToggle) { handlePostEditToggle(postEditToggle); return; }

			const postDelete = e.target.closest("[data-post-delete]");
			if (postDelete) { handlePostDelete(postDelete); return; }

			const postPin = e.target.closest("[data-post-pin-toggle]");
			if (postPin) { handlePostPinToggle(postPin); return; }

			const replyToggle = e.target.closest("[data-reply-toggle]");
			if (replyToggle) { handleReplyToggle(replyToggle); return; }

			const editToggle = e.target.closest("[data-edit-toggle]");
			if (editToggle) { handleEditToggle(editToggle); return; }

			const commentDelete = e.target.closest("[data-comment-delete]");
			if (commentDelete) { handleCommentDelete(commentDelete); return; }

			const subscribeBtn = e.target.closest("[data-subscribe-toggle]");
			if (subscribeBtn) { handleSubscribeToggle(subscribeBtn); return; }

			const privacyToggle = e.target.closest("[data-forum-privacy-toggle]");
			if (privacyToggle) { handleForumPrivacyToggle(privacyToggle); return; }

			const removeMod = e.target.closest("[data-remove-moderator]");
			if (removeMod) { handleRemoveModerator(removeMod); return; }

			const dashRemoveMod = e.target.closest("[data-dash-remove-moderator]");
			if (dashRemoveMod) { handleDashRemoveModerator(dashRemoveMod); return; }

			const removeMember = e.target.closest("[data-remove-member]");
			if (removeMember) { handleRemoveMember(removeMember); return; }

			const notifToggle = e.target.closest("[data-notifications-toggle]");
			if (notifToggle) { handleNotificationsToggle(notifToggle); return; }

			const postTypeTab = e.target.closest("[data-post-type-tab]");
			if (postTypeTab) { handleEditorTabClick(postTypeTab); return; }

			const mobileNavToggle = e.target.closest("[data-mobile-nav-toggle]");
			if (mobileNavToggle) { openMobileNav(); return; }

			const mobileNavClose = e.target.closest("[data-mobile-nav-close], [data-mobile-nav-backdrop]");
			if (mobileNavClose) { closeMobileNav(); return; }

			// A tap on any forum link inside the drawer should navigate AND close the drawer —
			// closing isn't strictly needed since the page is about to unload anyway, but it
			// avoids a flash of the open drawer on the new page if navigation is served from bfcache.
			const drawerLink = e.target.closest("[data-mobile-nav-drawer] a");
			if (drawerLink) { closeMobileNav(); }

			const usermenuToggle = e.target.closest("[data-usermenu-toggle]");
			if (usermenuToggle) { handleUsermenuToggle(usermenuToggle); return; }

			const logoutBtn = e.target.closest("[data-logout-btn]");
			if (logoutBtn) { handleLogout(); return; }

			const usermenuWidget = document.querySelector("[data-usermenu-widget]");
			if (usermenuWidget && !usermenuWidget.contains(e.target)) {
				const dropdown = usermenuWidget.querySelector("[data-usermenu-dropdown]");
				const toggle = usermenuWidget.querySelector("[data-usermenu-toggle]");
				if (dropdown && !isHidden(dropdown)) { hide(dropdown); if (toggle) toggle.setAttribute("aria-expanded", "false"); }
			}

			const achCard = e.target.closest("[data-ach-card]");
			if (achCard) { showAchievementDetail(achCard.dataset.achSlug); return; }

			const achBack = e.target.closest("[data-ach-back]");
			if (achBack) { e.preventDefault(); showAchievementGrid(); return; }

			const commentCollapse = e.target.closest("[data-comment-collapse]");
			if (commentCollapse) { DTGlobal.toggleComment(commentCollapse); return; }

			const achTierBtn = e.target.closest("[data-ach-tier-btn]");
			if (achTierBtn) { e.preventDefault(); showAchievementDetail(achTierBtn.dataset.slug, achTierBtn.dataset.tier); return; }

			const widget = document.querySelector("[data-notifications-widget]");
			if (widget && !widget.contains(e.target)) {
				const dropdown = widget.querySelector("[data-notifications-dropdown]");
				if (dropdown) hide(dropdown);
			}
		});

		document.addEventListener("change", (e) => {
			const modsForumSelect = e.target.closest("[data-mods-forum-select]");
			if (modsForumSelect) { handleModsForumSelectChange(modsForumSelect); return; }
		});

		document.addEventListener("blur", (e) => {
			if (e.target.matches && e.target.matches("[data-editor-link-input]")) { handleEditorLinkBlur(e.target); }
		}, true);

		document.addEventListener("submit", (e) => {
			if (e.target.matches("[data-post-edit-form]")) { e.preventDefault(); handlePostEditSubmit(e.target); return; }
			if (e.target.matches("[data-comment-form], [data-reply-form]")) { e.preventDefault(); handleCommentFormSubmit(e.target); return; }
			if (e.target.matches("[data-comment-edit-form]")) { e.preventDefault(); handleCommentEditSubmit(e.target); return; }
			if (e.target.matches("[data-settings-password-form]")) { e.preventDefault(); handlePasswordFormSubmit(e.target); return; }
			if (e.target.matches("[data-forum-details-form]")) { e.preventDefault(); handleForumDetailsSubmit(e.target); return; }
			if (e.target.matches("[data-add-moderator-form]")) { e.preventDefault(); handleAddModerator(e.target); return; }
			if (e.target.matches("[data-add-member-form]")) { e.preventDefault(); handleAddMember(e.target); return; }
			if (e.target.matches("[data-add-mod-form]")) { e.preventDefault(); handleDashAddModerator(e.target); return; }
			if (e.target.matches("[data-create-forum-form]")) { e.preventDefault(); handleCreateForumSubmit(e.target); return; }
		});
	}

	return { init: init, bumpNotificationBadge: bumpNotificationBadge };
}());

document.addEventListener("DOMContentLoaded", function () {
	DTActions.init();
});
