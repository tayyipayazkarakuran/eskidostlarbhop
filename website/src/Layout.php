<?php

declare(strict_types=1);

final class Layout
{
    public static function header(string $title, string $active = '', string $description = ''): void
    {
        global $config;
        $pageTitle = $title === '' ? $config['site_name'] : $title . ' — ' . $config['site_name'];
        $description = $description !== '' ? $description : 'Live CS 1.6 bunny hop records, maps and player rankings.';
        ?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark">
    <meta name="theme-color" content="#050505">
    <meta name="description" content="<?= Support::e($description) ?>">
    <title><?= Support::e($pageTitle) ?></title>
    <link rel="stylesheet" href="<?= Support::e(Support::asset('css/style.css')) ?>">
</head>
<body data-api-base="<?= Support::e($config['base_url']) ?>">
<a class="skip-link" href="#content">Skip to content</a>
<header class="site-header">
    <a class="wordmark" href="<?= Support::e(Support::url('/')) ?>" aria-label="ESKIDOSTLAR BHOP home">
        <span class="wordmark-mark" aria-hidden="true">ED</span>
        <span><strong>ESKIDOSTLAR</strong><small>BHOP / 1.6</small></span>
    </a>
    <nav class="site-nav" aria-label="Main navigation">
        <?= self::navLink('/', 'Timing', $active === 'home') ?>
        <?= self::navLink('/top-credits', 'Credits', $active === 'credits') ?>
        <?= self::navLink('/market', 'Market', $active === 'market') ?>
        <?= self::navLink('/badges', 'Badges', $active === 'badges') ?>
        <?= self::navLink('/motd', 'MOTD', false) ?>
    </nav>
    <div class="header-state" data-live-label>
        <span class="state-pip" aria-hidden="true"></span>
        <span>LIVE TIMING</span>
    </div>
</header>
        <?php
    }

    public static function footer(): void
    {
        global $config;
        ?>
<footer class="site-footer">
    <div>
        <span class="footer-title">ESKIDOSTLAR BHOP</span>
        <span>Competitive timing for Counter-Strike 1.6.</span>
    </div>
    <div class="footer-meta">
        <span>READ-ONLY MYSQL</span>
        <span>A2S LIVE STATUS</span>
        <span><?= Support::e($config['timezone']) ?></span>
    </div>
</footer>
<div class="toast" id="toast" role="status" aria-live="polite"></div>
<script src="<?= Support::e(Support::asset('js/app.js')) ?>" defer></script>
</body>
</html>
        <?php
    }

    public static function pageIntro(string $eyebrow, string $title, string $copy): void
    {
        ?>
<section class="page-intro">
    <p class="eyebrow"><?= Support::e($eyebrow) ?></p>
    <h1><?= Support::e($title) ?></h1>
    <p><?= Support::e($copy) ?></p>
</section>
        <?php
    }

    public static function alert(string $title, string $message, string $tone = 'warning'): void
    {
        ?>
<div class="alert alert-<?= Support::e($tone) ?>" role="status">
    <strong><?= Support::e($title) ?></strong>
    <span><?= Support::e($message) ?></span>
</div>
        <?php
    }

    public static function emptyState(string $title, string $message): void
    {
        ?>
<div class="empty-state">
    <span class="empty-glyph" aria-hidden="true">—</span>
    <strong><?= Support::e($title) ?></strong>
    <span><?= Support::e($message) ?></span>
</div>
        <?php
    }

    private static function navLink(string $path, string $label, bool $active): string
    {
        return sprintf(
            '<a href="%s"%s>%s</a>',
            Support::e(Support::url($path)),
            $active ? ' aria-current="page" class="is-active"' : '',
            Support::e($label),
        );
    }
}
