-- =============================================================================
-- bxThreads MySQL schema
--
-- Ground-truth DDL, dumped directly from a live `dismal` MySQL instance (the
-- same database the app's own developer built this schema against — see the
-- comment in views/user/achievements.bxm referencing it). This supersedes any
-- earlier reverse-engineered-from-application-code version: table shapes,
-- keys, and FK behavior here are exactly what's actually running.
--
-- Includes seed data for Achievements + AchievementTiers (the fixed catalog
-- of achievement definitions the app expects to exist — see
-- models/services/AchievementService.bx, which has no INSERT path for these
-- tables and reads them as pre-existing reference data), plus a single
-- sentinel row in Users for lib/Config.bx's defaultUser (anonymous/guest
-- sessions). No other tables are seeded; Forums/Posts/etc. start empty.
--
-- Apply with:  mysql -u root -p < db/schema.sql
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE DATABASE IF NOT EXISTS `dismal`
	CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE `dismal`;

-- =============================================================================
-- Users
-- =============================================================================
DROP TABLE IF EXISTS `Users`;
CREATE TABLE `Users` (
	`id`         BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`id_short`   VARCHAR(8)   GENERATED ALWAYS AS (LEFT(BIN_TO_UUID(`id`), 8)) STORED,
	`email`      VARCHAR(255) NOT NULL,
	`user_name`  VARCHAR(50)  NOT NULL,
	`password`   VARCHAR(255) DEFAULT NULL,
	`created_at` TIMESTAMP    NOT NULL DEFAULT (NOW()),
	`updated_at` TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `Users_user_name_uindex` (`user_name`) COMMENT 'Do not allow duplicate user_name values',
	UNIQUE KEY `Users_email_uindex` (`email`),
	UNIQUE KEY `Users_id_short_uindex` (`id_short`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Sentinel "anonymous" user — lib/Config.bx's defaultUser. Every logged-out
-- session, guest view record, and unauthenticated STOMP connection attributes
-- itself to this row, so it must exist before the app can serve a single
-- request. `password` stays NULL: this account can never be logged into.
INSERT INTO `Users` (`id`, `email`, `user_name`, `password`) VALUES
	(UUID_TO_BIN('010f3a4c-a127-11ef-b36c-b30d25967fba'), 'anonymous@localhost', 'anonymous', NULL);

-- =============================================================================
-- Permissions
-- =============================================================================
DROP TABLE IF EXISTS `Permissions`;
CREATE TABLE `Permissions` (
	`id`         BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`permission` VARCHAR(255) DEFAULT NULL,
	PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Forums
-- =============================================================================
DROP TABLE IF EXISTS `Forums`;
CREATE TABLE `Forums` (
	`id`              BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`id_short`        VARCHAR(8)   GENERATED ALWAYS AS (LEFT(BIN_TO_UUID(`id`), 8)) STORED,
	`display`         VARCHAR(50)  NOT NULL,
	`about`           TEXT,
	`icon`            VARCHAR(255) DEFAULT NULL,
	`owner`           BINARY(16)   NOT NULL,
	`deleted`         INT          DEFAULT '0',
	`created_at`      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at`      TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	`permissions_id`  BINARY(16)   DEFAULT NULL,
	`is_private`      TINYINT(1)   NOT NULL DEFAULT '0',
	PRIMARY KEY (`id`),
	UNIQUE KEY `Forums_display_uindex` (`display`) COMMENT 'require a uniqe display name',
	KEY `Forums_deleted_index` (`deleted`),
	KEY `Forums_id_short_index` (`id_short`),
	KEY `Forums_owner_fk` (`owner`),
	KEY `Forums_permissions_fk` (`permissions_id`),
	CONSTRAINT `Forums_owner_fk` FOREIGN KEY (`owner`) REFERENCES `Users` (`id`) ON DELETE RESTRICT,
	CONSTRAINT `Forums_permissions_fk` FOREIGN KEY (`permissions_id`) REFERENCES `Permissions` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- UsersPermissions (join table: user <-> permission)
-- =============================================================================
DROP TABLE IF EXISTS `UsersPermissions`;
CREATE TABLE `UsersPermissions` (
	`users_id`       BINARY(16) NOT NULL,
	`permissions_id` BINARY(16) NOT NULL,
	PRIMARY KEY (`users_id`, `permissions_id`),
	KEY `UsersPermissions_users_id_index` (`users_id`),
	KEY `UsersPermissions_Permissions_id_fk` (`permissions_id`),
	CONSTRAINT `UsersPermissions_Permissions_id_fk` FOREIGN KEY (`permissions_id`) REFERENCES `Permissions` (`id`) ON DELETE CASCADE,
	CONSTRAINT `UsersPermissions_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- UsersForums (join table: forum subscriptions)
-- =============================================================================
DROP TABLE IF EXISTS `UsersForums`;
CREATE TABLE `UsersForums` (
	`users_id`  BINARY(16) NOT NULL,
	`forums_id` BINARY(16) NOT NULL,
	PRIMARY KEY (`users_id`, `forums_id`),
	KEY `UsersForums_users_id_index` (`users_id`),
	KEY `UsersForums_Forums_id_fk` (`forums_id`),
	KEY `idx_usersforums_user_forum` (`users_id`, `forums_id`),
	CONSTRAINT `UsersForums_Forums_id_fk` FOREIGN KEY (`forums_id`) REFERENCES `Forums` (`id`) ON DELETE CASCADE,
	CONSTRAINT `UsersForums_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Links
-- =============================================================================
DROP TABLE IF EXISTS `Links`;
CREATE TABLE `Links` (
	`id`          BINARY(16)    NOT NULL,
	`users_id`    BINARY(16)    DEFAULT NULL,
	`title`       VARCHAR(500)  DEFAULT NULL,
	`description` TEXT,
	`image`       VARCHAR(1000) DEFAULT NULL,
	`url`         VARCHAR(1000) DEFAULT NULL,
	`created_at`  TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at`  TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uq_links_url` (`url`(768)),
	KEY `Links_Users_id_fk` (`users_id`),
	CONSTRAINT `Links_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Posts
-- =============================================================================
DROP TABLE IF EXISTS `Posts`;
CREATE TABLE `Posts` (
	`id`         BINARY(16)  NOT NULL,
	`id_short`   VARCHAR(8)  GENERATED ALWAYS AS (LEFT(BIN_TO_UUID(`id`), 8)) STORED,
	`forums_id`  BINARY(16)  NOT NULL,
	`users_id`   BINARY(16)  NOT NULL,
	`post_type`  VARCHAR(255) DEFAULT NULL,
	`title`      VARCHAR(500) DEFAULT NULL,
	`body`       TEXT,
	`deleted`    INT          DEFAULT '0',
	`pinned`     TINYINT(1)   NOT NULL DEFAULT '0',
	`pinned_at`  DATETIME     DEFAULT NULL,
	`created_at` TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at` TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `Posts_created_at_index` (`created_at`),
	KEY `Posts_deleted_index` (`deleted`),
	KEY `Posts_id_short_index` (`id_short`),
	KEY `idx_posts_deleted_created` (`deleted`, `created_at` DESC),
	KEY `idx_posts_user_type_deleted` (`users_id`, `post_type`, `deleted`),
	KEY `idx_posts_forum_pinned` (`forums_id`, `pinned`, `pinned_at`),
	FULLTEXT KEY `ft_posts_search` (`title`, `body`),
	CONSTRAINT `Posts_Forums_id_fk` FOREIGN KEY (`forums_id`) REFERENCES `Forums` (`id`) ON DELETE CASCADE,
	CONSTRAINT `Posts_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- PostsLinks (join table: post <-> its scraped link)
-- =============================================================================
DROP TABLE IF EXISTS `PostsLinks`;
CREATE TABLE `PostsLinks` (
	`posts_id` BINARY(16) NOT NULL,
	`links_id` BINARY(16) NOT NULL,
	PRIMARY KEY (`posts_id`, `links_id`),
	KEY `PostsLinks_Links_id_fk` (`links_id`),
	KEY `PostsLinks_posts_id_index` (`posts_id`),
	CONSTRAINT `PostsLinks_Links_id_fk` FOREIGN KEY (`links_id`) REFERENCES `Links` (`id`) ON DELETE CASCADE,
	CONSTRAINT `PostsLinks_Posts_id_fk` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Comments
-- =============================================================================
DROP TABLE IF EXISTS `Comments`;
CREATE TABLE `Comments` (
	`id`         BINARY(16)    NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`id_short`   VARCHAR(8)    GENERATED ALWAYS AS (LEFT(BIN_TO_UUID(`id`), 8)) STORED,
	`parent_id`  BINARY(16)    DEFAULT NULL,
	`forums_id`  BINARY(16)    NOT NULL,
	`posts_id`   BINARY(16)    NOT NULL,
	`users_id`   BINARY(16)    NOT NULL,
	`body`       VARCHAR(10000) NOT NULL,
	`deleted`    INT           NOT NULL DEFAULT '0',
	`created_at` TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at` TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `Comments_id_short_uindex` (`id_short`),
	KEY `Comments_Forums_id_fk` (`forums_id`),
	KEY `Comments_parent_fk` (`parent_id`),
	KEY `idx_comments_posts_deleted` (`posts_id`, `deleted`),
	KEY `idx_comments_user_deleted` (`users_id`, `deleted`),
	CONSTRAINT `Comments_Forums_id_fk` FOREIGN KEY (`forums_id`) REFERENCES `Forums` (`id`) ON DELETE CASCADE,
	CONSTRAINT `Comments_parent_fk` FOREIGN KEY (`parent_id`) REFERENCES `Comments` (`id`) ON DELETE SET NULL,
	CONSTRAINT `Comments_Posts_id_fk` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `Comments_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Votes
-- =============================================================================
DROP TABLE IF EXISTS `Votes`;
CREATE TABLE `Votes` (
	`id`          BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`    BINARY(16) NOT NULL,
	`posts_id`    BINARY(16) DEFAULT NULL,
	`comments_id` BINARY(16) DEFAULT NULL,
	`vote`        TINYINT    NOT NULL,
	`created_at`  TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uq_user_post` (`users_id`, `posts_id`),
	UNIQUE KEY `uq_user_comment` (`users_id`, `comments_id`),
	KEY `idx_votes_posts_id` (`posts_id`),
	KEY `idx_votes_user_post` (`users_id`, `posts_id`),
	KEY `idx_votes_comments_id` (`comments_id`),
	KEY `idx_votes_post_comment` (`posts_id`, `comments_id`),
	CONSTRAINT `fk_votes_comment` FOREIGN KEY (`comments_id`) REFERENCES `Comments` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_votes_post` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_votes_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE,
	CONSTRAINT `chk_one_target` CHECK (((`posts_id` IS NOT NULL AND `comments_id` IS NULL) OR (`posts_id` IS NULL AND `comments_id` IS NOT NULL))),
	CONSTRAINT `chk_vote_value` CHECK ((`vote` IN (-1, 1)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Bookmarks
-- =============================================================================
DROP TABLE IF EXISTS `Bookmarks`;
CREATE TABLE `Bookmarks` (
	`id`         BINARY(16) NOT NULL,
	`users_id`   BINARY(16) NOT NULL,
	`posts_id`   BINARY(16) NOT NULL,
	`created_at` TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uq_user_post` (`users_id`, `posts_id`),
	KEY `fk_bookmarks_post` (`posts_id`),
	CONSTRAINT `fk_bookmarks_post` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_bookmarks_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Notifications
-- =============================================================================
DROP TABLE IF EXISTS `Notifications`;
CREATE TABLE `Notifications` (
	`id`          BINARY(16)  NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`    BINARY(16)  NOT NULL,
	`actor_id`    BINARY(16)  NOT NULL,
	`posts_id`    BINARY(16)  DEFAULT NULL,
	`comments_id` BINARY(16)  DEFAULT NULL,
	`type`        VARCHAR(50) NOT NULL,
	`meta`        JSON        DEFAULT NULL,
	`is_read`     TINYINT     NOT NULL DEFAULT '0',
	`created_at`  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `fk_notif_actor` (`actor_id`),
	KEY `fk_notif_post` (`posts_id`),
	KEY `fk_notif_comment` (`comments_id`),
	KEY `idx_notif_user_read` (`users_id`, `is_read`),
	CONSTRAINT `fk_notif_actor` FOREIGN KEY (`actor_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_notif_comment` FOREIGN KEY (`comments_id`) REFERENCES `Comments` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_notif_post` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_notif_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- History (post view log)
-- =============================================================================
DROP TABLE IF EXISTS `History`;
CREATE TABLE `History` (
	`id`         BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`   BINARY(16) NOT NULL,
	`forums_id`  BINARY(16) DEFAULT NULL,
	`posts_id`   BINARY(16) NOT NULL,
	`created_at` TIMESTAMP  NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `History_Forums_id_fk` (`forums_id`),
	KEY `History_Posts_id_fk` (`posts_id`),
	KEY `History_Users_id_fk` (`users_id`),
	KEY `History_created_at_index` (`created_at`),
	CONSTRAINT `History_Forums_id_fk` FOREIGN KEY (`forums_id`) REFERENCES `Forums` (`id`) ON DELETE SET NULL,
	CONSTRAINT `History_Posts_id_fk` FOREIGN KEY (`posts_id`) REFERENCES `Posts` (`id`) ON DELETE CASCADE,
	CONSTRAINT `History_Users_id_fk` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Activities (append-only user action log)
-- =============================================================================
DROP TABLE IF EXISTS `Activities`;
CREATE TABLE `Activities` (
	`id`          BINARY(16)  NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`    BINARY(16)  NOT NULL,
	`action`      VARCHAR(30) NOT NULL,
	`target_type` VARCHAR(20) DEFAULT NULL,
	`target_id`   BINARY(16)  DEFAULT NULL,
	`meta`        JSON        DEFAULT NULL,
	`created_at`  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `idx_activities_user_created` (`users_id`, `created_at` DESC),
	KEY `idx_activities_action_user` (`action`, `users_id`),
	KEY `idx_activities_created` (`created_at` DESC),
	CONSTRAINT `fk_activities_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- Achievements (seeded below — fixed catalog, no in-app INSERT path)
-- =============================================================================
DROP TABLE IF EXISTS `Achievements`;
CREATE TABLE `Achievements` (
	`id`         BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`id_short`   VARCHAR(8)   NOT NULL,
	`slug`       VARCHAR(50)  NOT NULL,
	`category`   VARCHAR(100) NOT NULL,
	`name`       VARCHAR(100) NOT NULL,
	`secret`     TINYINT      NOT NULL DEFAULT '0',
	`metric`     VARCHAR(30)  NOT NULL DEFAULT 'threshold',
	`sort_order` INT          NOT NULL DEFAULT '0',
	`created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `idx_achievements_slug` (`slug`),
	UNIQUE KEY `idx_achievements_id_short` (`id_short`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- AchievementTiers (seeded below, 5 tiers per achievement)
-- =============================================================================
DROP TABLE IF EXISTS `AchievementTiers`;
CREATE TABLE `AchievementTiers` (
	`id`              BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`achievements_id` BINARY(16)   NOT NULL,
	`tier`            TINYINT      NOT NULL,
	`label`           VARCHAR(50)  NOT NULL,
	`threshold`       VARCHAR(100) NOT NULL,
	`threshold_value` INT          NOT NULL DEFAULT '0',
	`threshold_max`   INT          DEFAULT NULL,
	`title`           VARCHAR(255) NOT NULL,
	`flavor`          TEXT         NOT NULL,
	PRIMARY KEY (`id`),
	UNIQUE KEY `idx_achievementtiers_achievement_tier` (`achievements_id`, `tier`),
	CONSTRAINT `fk_achievementtiers_achievement` FOREIGN KEY (`achievements_id`) REFERENCES `Achievements` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- UserAchievements (per-user awards — starts empty)
-- =============================================================================
DROP TABLE IF EXISTS `UserAchievements`;
CREATE TABLE `UserAchievements` (
	`id`              BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`        BINARY(16) NOT NULL,
	`achievements_id` BINARY(16) NOT NULL,
	`current_tier`    TINYINT    NOT NULL DEFAULT '1',
	`unlocked_at`     TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`updated_at`      TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `idx_userachievements_user_achievement` (`users_id`, `achievements_id`),
	KEY `fk_userachievements_achievement` (`achievements_id`),
	KEY `idx_userachievements_user` (`users_id`),
	CONSTRAINT `fk_userachievements_achievement` FOREIGN KEY (`achievements_id`) REFERENCES `Achievements` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_userachievements_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- UserStreaks (per-user daily-activity streak — starts empty)
-- =============================================================================
DROP TABLE IF EXISTS `UserStreaks`;
CREATE TABLE `UserStreaks` (
	`users_id`           BINARY(16)          NOT NULL,
	`current_streak`     SMALLINT UNSIGNED   NOT NULL DEFAULT '0',
	`longest_streak`     SMALLINT UNSIGNED   NOT NULL DEFAULT '0',
	`last_activity_date` DATE                NOT NULL,
	`updated_at`         TIMESTAMP           NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`users_id`),
	CONSTRAINT `fk_userstreaks_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- =============================================================================
-- UserAchievementHistory (append-only tier-award log — starts empty)
-- =============================================================================
DROP TABLE IF EXISTS `UserAchievementHistory`;
CREATE TABLE `UserAchievementHistory` (
	`id`              BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),
	`users_id`        BINARY(16) NOT NULL,
	`achievements_id` BINARY(16) NOT NULL,
	`tier_id`         BINARY(16) NOT NULL,
	`tier_number`     TINYINT    NOT NULL,
	`unlocked_at`     TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	KEY `idx_uah_user` (`users_id`),
	KEY `idx_uah_user_achievement` (`users_id`, `achievements_id`),
	KEY `fk_uah_achievement` (`achievements_id`),
	KEY `fk_uah_tier` (`tier_id`),
	CONSTRAINT `fk_uah_achievement` FOREIGN KEY (`achievements_id`) REFERENCES `Achievements` (`id`) ON DELETE CASCADE,
	CONSTRAINT `fk_uah_tier` FOREIGN KEY (`tier_id`) REFERENCES `AchievementTiers` (`id`) ON DELETE RESTRICT,
	CONSTRAINT `fk_uah_user` FOREIGN KEY (`users_id`) REFERENCES `Users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- Seed data: Achievements
-- =============================================================================
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00001', 'account_age', 'Longevity', 'Still Here', 0, 'account_days', 1);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00002', 'total_contributions', 'Contributions', 'Showing Up', 0, 'contribution_count', 2);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00003', 'long_form_writer', 'Contributions', 'The Long Form', 0, 'post_count', 3);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00004', 'curator', 'Contributions', 'Always Finding Things', 0, 'link_count', 4);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00011', 'comments_made', 'Contributions', 'In the Replies', 0, 'comment_count', 5);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00005', 'likes_received', 'Recognition', 'People Actually Like You', 0, 'likes_received', 6);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00006', 'likes_given', 'Recognition', 'Surprisingly Generous', 0, 'likes_given', 7);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00007', 'replies', 'Engagement', 'Actual Conversations', 0, 'reply_count', 8);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00008', 'streaks', 'Consistency', 'Showing Up', 0, 'streak_days', 9);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 'ACH00012', 'deep_reader', 'Engagement', 'The Reader', 0, 'load_more_count', 9);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00009', 'secret_ghost', 'Secret', 'Ghost Member', 1, 'account_days_max_posts', 10);
INSERT INTO `Achievements` (`id`, `id_short`, `slug`, `category`, `name`, `secret`, `metric`, `sort_order`) VALUES (UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 'ACH00010', 'secret_comeback', 'Secret', 'Lazarus Account', 1, 'absence_days', 11);

-- =============================================================================
-- Seed data: AchievementTiers (5 tiers each)
-- =============================================================================
-- account_age
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c120e434-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 1, 'Newly Registered', 'Account 1 day old', 1, NULL, 'You Made an Account. Bold Move.', 'You filled out the form. You confirmed the email. You are, technically, a member of this community. What you do with that is entirely your problem.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1210b44-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 2, 'One Week In', 'Account 7 days old', 7, NULL, 'Still Logged In After Seven Days', 'Most people make an account, poke around for a few days, and disappear forever. You haven''t done that yet. It''s been a week. The forum has noticed, in the way a forum notices things — silently, without comment.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1210d74-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Regular', 'Account 30 days old', 30, NULL, 'You''re Kind of a Regular Now', 'A month. You''ve seen enough threads to have opinions about how things work around here. You probably have one or two already. The forum isn''t going to confirm or deny whether those opinions are correct.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1210e64-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Veteran', 'Account 1 year old', 365, NULL, 'A Year of This', 'You''ve been here twelve months. The forum has changed in small ways you''ve probably stopped noticing. You changed too, probably. Neither of you has mentioned it. That''s fine. That''s how it goes.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1210f86-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b587186-53a5-11f1-a33a-e1aec1bf7920'), 5, 'Furniture', 'Account 3+ years old', 1095, NULL, 'You Are Part of the Place Now', 'Three years. New members will find your old posts in searches and not realize you''re still active. Some of them will assume you''re a legend. Some will assume you''re a bot. You''re neither. You just kept showing up. Honestly, that''s more impressive than either.');

-- total_contributions
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1234896-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 1, 'First One', '1 contribution', 1, NULL, 'You Posted Something.', 'It is out there now. A post or a link, doesn''t matter which. You put something into the forum and the forum received it. That''s the whole thing for now.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1235228-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Getting Going', '25 contributions', 25, NULL, 'Twenty-Five Things You Decided Were Worth Sharing', 'Twenty-five posts or links. You''re past the point of just testing the water. You have a sense of what this place is and you''re contributing to it. The forum has a slightly better sense of who you are because of it.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c123534a-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Contributor', '100 contributions', 100, NULL, 'A Hundred Contributions and Still Going', 'One hundred posts and links combined. That''s a hundred moments where you had something — an idea, an article, a thought — and decided to share it here instead of keeping it to yourself. The forum is measurably richer for that. Not dramatically. But measurably.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12353fe-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Prolific', '500 contributions', 500, NULL, 'You''ve Been Putting Things Into This Place', 'Five hundred contributions. Some of them landed well. Some of them didn''t. That''s true of anyone who posts this much. The point isn''t the hit rate — it''s that you kept showing up and kept sharing things. That''s what a forum runs on.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12354a8-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a11f8-53a5-11f1-a33a-e1aec1bf7920'), 5, 'Foundational', '2,000+ contributions', 2000, NULL, 'The Forum Has a Lot of You In It', 'Two thousand contributions. Posts and links and everything in between. At this point you are part of the substrate — the accumulated weight of what this place actually is. New members will inherit context from things you shared without knowing it came from you. The forum does.');

-- long_form_writer
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1253c6e-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 1, 'First Draft', '1 long-form post', 1, NULL, 'You Wrote Something.', 'Not a link. Not a quick share. You sat down and wrote something. However long or short, it came from you. The forum has that now.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c125422c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Finding the Voice', '10 long-form posts', 10, NULL, 'Ten Posts In and Still Writing', 'Ten long-form posts. You''ve written enough that a shape is emerging — the things you come back to, the way you put sentences together, the topics that get you going. You might not see it yet. Other people are starting to.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1254344-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 3, 'The Writer', '50 long-form posts', 50, NULL, 'Fifty Posts That Didn''t Have to Exist', 'Fifty long-form posts. Every one of them was a choice — to write the thing instead of just thinking it, to post it instead of leaving it in drafts. That''s not nothing. Writing for a forum is writing into a room of people who didn''t ask for it. You keep doing it anyway. Some of them are glad you do.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1254452-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 4, 'The Regular Voice', '150 long-form posts', 150, NULL, 'People Come Here Partly Because You Write Here', 'A hundred and fifty posts. There are people on this forum who have read more of your writing than they''ve read of most published authors they''d claim to enjoy. They probably haven''t said so. That''s how reading works. The forum knows, even if the readers don''t say it out loud.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12544fc-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a23f0-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Chronicler', '500+ long-form posts', 500, NULL, 'You Have Written This Place Into Existence, Partly', 'Five hundred long-form posts. Somewhere across those posts is an account of what this community has been — what it argued about, what it cared about, what it found funny or wrong or worth saying. You didn''t set out to document anything. You just kept writing. That''s usually how the record gets made.');

-- curator
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c126ea28-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 1, 'First Find', '1 link shared', 1, NULL, 'You Found Something Worth Sharing.', 'One link. You were somewhere on the internet, you found a thing, and you decided this was the right place to bring it. That''s a small judgment call. You made it correctly, probably.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c126ef14-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Always Reading', '25 links shared', 25, NULL, 'You''re Always Finding Things', 'Twenty-five links. You read more than most people. Or you move through the internet differently — noticing things others scroll past, tabbing them, bringing them back. The forum benefits from this in ways that are hard to quantify and easy to take for granted.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c126f018-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 3, 'The Feed', '100 links shared', 100, NULL, 'There''s a Whole Internet Out There and You''re In It', 'A hundred links shared. At this point people have probably started paying attention to what you post specifically — not just skimming the feed but looking for your name, because the last thing you shared was good and they want to see what''s next. You may not have noticed. They''re not going to mention it.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c126f0cc-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Compulsive Finder', '350 links shared', 350, NULL, 'You Cannot Stop Bringing Things Back', 'Three hundred and fifty links. This is a compulsion now, and not a bad one. You find things. You share them. Some of them matter to people in ways you''ll never know — an article that changed someone''s mind, a tool someone''s still using three years later, a piece of writing someone''s quoted in an argument since. You''ll never find out which ones.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c126f16c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2508-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Source', '1,000+ links shared', 1000, NULL, 'People Find Things Through You They Wouldn''t Find Otherwise', 'A thousand links. Do the math on what that means — a thousand times you found something, decided it was worth other people''s time, and brought it here. The forum''s collective knowledge of what''s out there is shaped by you more than by almost anyone else. That''s a strange kind of authorship. It counts anyway.');

-- comments_made
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c128863a-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 1, 'First Reply', '1 comment', 1, NULL, 'You Replied to Someone.', 'You read what someone wrote and had something to say back. That''s it. That''s the whole thing. The forum is built out of exactly this, repeated.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1288c5c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Regular Commenter', '25 comments', 25, NULL, 'You''re in the Replies', 'Twenty-five comments. You''re the kind of person who reads a post and then says something about it, instead of just reading and moving on. This is more unusual than it sounds. Most people just move on.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1288d4c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 3, 'The Reactor', '100 comments', 100, NULL, 'Something About Other People''s Posts Gets You Going', 'A hundred comments. You have a specific relationship with this forum — you don''t just show up to say your piece, you show up to engage with what other people are saying. Threads you''re in tend to have more going on than threads you''re not. People may not have articulated this. It''s true anyway.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1288dec-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Lives in the Replies', '500 comments', 500, NULL, 'Other People''s Threads Are Kind of Your Home', 'Five hundred comments. You have left a piece of yourself in other people''s conversations more times than most people start their own. There''s a whole mode of being on a forum that this represents — not the person at the front of the room but the person whose voice you keep hearing from the floor, and who keeps making it better.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1288ea0-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a25b2-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Reply Guy', '2,000+ comments', 2000, NULL, 'Wherever Something is Being Said, There You Are', 'Two thousand comments. Not posts — comments. Every one of them was a response to something someone else made. You have given more of your time and attention to other people''s work than most people give to their own. The forum doesn''t have a clean way to account for this. The people whose threads you''ve been in do.');

-- likes_received
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12a1284-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 1, 'Acknowledged', '1 like', 1, NULL, 'Someone Hit the Button', 'One person read what you wrote and decided it was worth a click. It costs nothing and they did it anyway. Don''t read too much into it. Don''t read too little either.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12a1c5c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Appreciated', '50 likes', 50, NULL, 'Fifty Times Someone Agreed', 'Fifty likes spread across your posts. You are saying things that land. Whatever it is you''re doing — the way you phrase things, the points you make, the timing — it''s working. The forum isn''t going to explain why. It just keeps clicking.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12a1da6-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Well-Regarded', '250 likes', 250, NULL, 'People Look Forward to What You Post', 'Two hundred and fifty likes. At some point this stopped being about individual posts and started being about you. People have started to have expectations. Quietly, without saying anything. That''s how it works here.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12a1e64-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Popular', '1,000 likes', 1000, NULL, 'A Thousand Moments of Somebody Agreeing With You', 'A thousand likes. You have influence here, even if you don''t think of it that way. People read your posts more carefully than they read most. Some have changed their mind because of something you wrote. They probably didn''t tell you. They rarely do.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12a1f2c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a26ca-53a5-11f1-a33a-e1aec1bf7920'), 5, 'Beloved', '5,000+ likes', 5000, NULL, 'The Forum Would Miss You', 'Five thousand likes. Not loudly. Not with a ceremony. But if you stopped posting tomorrow, there would be a gap — a specific shape of absence that no one else would fill in quite the same way. The forum has noticed what you bring to it. This is the closest it gets to saying so.');

-- likes_given
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12c254c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 1, 'First Nod', '1 like given', 1, NULL, 'You Acknowledged Someone Else Exists', 'You liked a post. You didn''t have to. You were under no obligation. The forum has recorded this as an unremarkable but quietly decent thing to do.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12c31f4-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Engaged', '50 likes given', 50, NULL, 'You''re Actually Reading the Replies', 'Fifty likes distributed. You''re paying attention. Not just to your own threads — to other people''s. That distinction matters more than most people realize.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12c33c0-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Generous', '200 likes given', 200, NULL, 'You Make People Feel Like They''re Worth Reading', 'Two hundred likes out the door. Somewhere in there, someone posted something they weren''t sure about, and you liked it, and they kept going. They don''t know it was you. It was still you.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12c3532-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Magnanimous', '750 likes given', 750, NULL, 'You Show Up for Other People''s Stuff', 'Seven hundred and fifty likes. At this point it''s a habit — a good one. You read things. You respond to them. You tell people, in the small quiet language of a like, that their post was worth the time it took. More people should do this. Not everyone does.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12c369a-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2792-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Good Kind of Regular', '2,500+ likes given', 2500, NULL, 'You Are One of the Reasons This Place Works', 'Two thousand five hundred likes given. The forum runs on people who post well and people who engage well. You are the second kind. Some people become something more important than a prolific poster: someone who makes the rest of the forum feel like it''s worth being in. That''s you.');

-- replies
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12d8ce8-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 1, 'In the Thread', 'First reply', 1, NULL, 'You Responded to Someone', 'You left a reply. Someone will read it. A thread that might have died got one more post. This sounds small. It isn''t always.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12d91fc-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Back and Forth', '50 replies', 50, NULL, 'You''re Having Conversations Here', 'Fifty replies in. You''re not just broadcasting — you''re talking to people. There''s a difference. Most forums are full of the first kind. The second kind is what makes a forum worth coming back to.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12d9300-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Thread Regular', '200 replies', 200, NULL, 'You Follow Through', 'Two hundred replies. You don''t just drop a comment and vanish. You come back. You read what people said. You respond. Threads with you in them tend to go somewhere. That''s not a coincidence.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12d93a0-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Discussion Anchor', '750 replies', 750, NULL, 'Things Get More Interesting When You''re Involved', 'Seven hundred and fifty. You have a gift — or a habit, which is sometimes better — for engaging in a way that invites more engagement. Your replies generate replies. Your questions get answered and then discussed. The forum feeds on this. Gladly.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12d944a-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2832-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Thread', '2,500+ replies', 2500, NULL, 'The Forum is Better When You''re In It', 'Two thousand five hundred replies. People have learned things in threads you were part of. Changed their minds. Laughed. Felt less alone about something. You won''t know which moments or which people. The forum does.');

-- deep_reader
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('aead9406-553e-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 1, 'Still Reading', '10 pages loaded', 10, NULL, 'You Didn''t Stop at the First Page', 'Most people see the end of the initial load and move on. You hit the button. You wanted to know what else was there. That''s a small thing. It''s also not nothing.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('aeae02ec-553e-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 2, 'Goes All the Way Down', '50 pages loaded', 50, NULL, 'You Actually Read the Whole Thing', 'Fifty load-mores. You have sat with threads and feeds long enough to exhaust them, more than once. There is content on this forum that most people have never seen because they didn''t scroll far enough. You have seen it.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('aeae042c-553e-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 3, 'The Reader', '200 pages loaded', 200, NULL, 'Most People Don''t Get This Far', 'Two hundred times you reached the bottom of a page and decided there was more worth reading. The forum is deeper than it looks from the top. You know this because you''ve checked. Repeatedly.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('aeae04d6-553e-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 4, 'Thorough', '750 pages loaded', 750, NULL, 'You Have Read Things Nobody Else Read', 'Seven hundred and fifty load-mores. Somewhere in there you have read posts that got no likes, comments that were never replied to, threads that died quietly after three replies. You were there. You read them. The people who wrote them never knew anyone did. You did.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('aeae1304-553e-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('aea65b96-553e-11f1-a33a-e1aec1bf7920'), 5, 'The Archivist', '2,500+ pages loaded', 2500, NULL, 'You Have Been Paying Attention This Whole Time', 'Two thousand five hundred. You have read this forum in a way that almost no one else has — not just the surface of it, not just the posts that rose to the top, but the long tail of it, the stuff that kept going past the fold. The forum is not just what gets written. It''s what gets read. You''re a significant part of that equation.');

-- streaks
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12f2de6-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 1, 'Back Again', '3-day streak', 3, NULL, 'You Came Back Three Days Running', 'You could have done other things. You came back anyway. Three days in a row. The forum clocked it without fanfare, the way forums do.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12f335e-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Habitual', '7-day streak', 7, NULL, 'A Full Week', 'Seven consecutive days. You''ve made this part of your routine, whether you thought of it that way or not. Habits are just things you keep doing. This is one of yours now.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12f346c-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Committed', '30-day streak', 30, NULL, 'A Month Without Missing a Day', 'Thirty days straight. In that time you probably had days where this was the last thing you felt like doing. You did it anyway. The forum doesn''t know why. It only knows that you showed up, and it mattered.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12f3516-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 4, 'Dependable', '90-day streak', 90, NULL, 'Three Months of Not Letting It Slide', 'Ninety consecutive days. The forum has regulars and then it has the kind of regulars other regulars rely on without realizing it — the ones who are always there when a thread needs one more thoughtful post, one more person reading. That''s what ninety days makes you.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c12f52a8-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2f1c-53a5-11f1-a33a-e1aec1bf7920'), 5, 'Unwavering', '365-day streak', 365, NULL, 'A Full Year. Every Single Day.', 'Three hundred and sixty-five days. You had other things going on. Everyone does. And still, every day for a year, you came back here. The forum doesn''t know what that cost you in small moments and tired evenings. It just knows you never stopped. That''s the whole achievement. That''s all of it.');

-- secret_ghost
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c130f31a-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 1, 'Lurker', '30+ days, 0 posts', 30, 0, 'You''re Reading Everything and Saying Nothing', 'A month in and not a single post. You''re watching. The forum is fine with this. It''s always had more readers than writers. You''re just further along that end of the scale than most.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c130f842-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Shadow Member', '90+ days, fewer than 5 posts', 90, 4, 'Three Months, Almost No Words', 'Ninety days. Fewer than five posts. You''ve been here long enough to have a feel for the place without ever really letting the place have a feel for you. There''s a kind of discipline in that. Or a kind of privacy. Maybe both.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c130f950-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 3, 'The Quiet Type', '6+ months, fewer than 10 posts', 180, 9, 'Six Months and Still Mostly Invisible', 'Half a year. The long-timers have probably noticed your username in the member list and wondered. You haven''t given them much to go on. The forum respects a closed book. It doesn''t love them, but it respects them.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c130f9fa-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 4, 'The Silent Regular', '1+ year, fewer than 20 posts', 365, 19, 'A Year Here and Still Keeping Your Own Counsel', 'A full year. Fewer than twenty posts. You have read arguments you could have settled, threads you could have contributed to, questions you probably knew the answer to. You stayed quiet. Whatever your reasons, they''re yours. The forum has stopped waiting.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c130faae-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a2fbc-53a5-11f1-a33a-e1aec1bf7920'), 5, 'Permanent Observer', '3+ years, fewer than 50 posts', 1095, 49, 'You Know This Place Better Than Most People Who Post Here', 'Three years. Under fifty posts. You have watched this community through changes and arguments and running jokes and the slow turnover of who''s who. You know more about this forum than people who post ten times a day. You just don''t say so. The forum has accepted this about you. It''s stopped being surprised.');

-- secret_comeback
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1329616-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 1, 'Returned', 'Post after 30+ days absent', 30, NULL, 'Back After a Month Away', 'You went quiet for thirty days and then posted like nothing happened. The forum made a note. It''s seen people leave before. Not everyone comes back.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1329b34-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 2, 'Came Back', 'Post after 90+ days absent', 90, NULL, 'Three Months Gone, Then Here Again', 'A quarter of a year. Then a post. You had something going on — the forum doesn''t know what, doesn''t need to. It just noticed the gap and then noticed you filling it again. That''s enough.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1329c42-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 3, 'Long Absence', 'Post after 6+ months absent', 180, NULL, 'Six Months and Then, Quietly, You Were Back', 'Half a year of silence. Then a post in a thread like you''d never left. A few people noticed. One of them probably said ''welcome back'' and you probably said thanks and didn''t explain further. That''s the right way to do it.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1329cec-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 4, 'The Long Way Back', 'Post after 1+ year absent', 365, NULL, 'A Year Away is a Long Time to Come Back From', 'Twelve months gone. Things changed while you were out — some threads closed, some regulars drifted, some arguments got resolved and new ones started up. You came back anyway, to a place that had kept going without you. That takes something. The forum doesn''t know what to call it. It''s calling it this.');
INSERT INTO `AchievementTiers` (`id`, `achievements_id`, `tier`, `label`, `threshold`, `threshold_value`, `threshold_max`, `title`, `flavor`) VALUES (UUID_TO_BIN('c1329d96-53a5-11f1-a33a-e1aec1bf7920'), UUID_TO_BIN('9b5a319c-53a5-11f1-a33a-e1aec1bf7920'), 5, 'The Return', 'Post after 2+ years absent', 730, NULL, 'Two Years. And Then You Posted.', 'Two years. The forum moved on, the way forums do. Your profile sat there. And then one day you posted something, and anyone who''d been here long enough did a small double-take, and the thread kept going, and you were just — back. Like a long gap in a conversation that someone finally decided to close. The forum is glad you closed it.');

-- =============================================================================
-- ClusterCache — boxlang-express's cluster.enabled peer discovery/manager
-- election (see boxlang.json's modules.boxexpress.settings.cluster and
-- app.bxs's app.getClusterManager()). BoxLang's own JDBCStore cache-provider
-- table, MySQL variant — exact shape it expects (confirmed directly against
-- the installed BoxLang 1.17.3 runtime's JDBCStore.class, since the auto-create
-- path is documented as unreliable and this app deliberately runs with
-- autoCreate: false instead). No seed data — every row here is written by
-- ClusterManager.bx's own heartbeat/manager-election calls at runtime.
-- =============================================================================
DROP TABLE IF EXISTS `ClusterCache`;
CREATE TABLE `ClusterCache` (
	objectKey VARCHAR(500) PRIMARY KEY,
	objectValue LONGTEXT,
	hits BIGINT DEFAULT 0,
	created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	lastAccessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	timeout BIGINT DEFAULT 0,
	lastAccessTimeout BIGINT DEFAULT 0,
	INDEX idx_lastAccessed (lastAccessed),
	INDEX idx_created (created),
	INDEX idx_hits (hits),
	INDEX idx_timeout (timeout, lastAccessTimeout)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
