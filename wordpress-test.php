<?php
/**
 * Plugin Name: WordPress Codespace
 * Plugin URI:  https://github.com/pjd199/wordpress-test
 * Description: A simple test plugin to verify the Codespace development environment is working.
 * Version:     1.0.0
 * Author:      pjd199
 */

defined('ABSPATH') || exit;

// Add a visible banner at the top of every page
add_action('wp_footer', function () {
    echo '<div style="
        position: fixed;
        bottom: 0; left: 0; right: 0;
        background: #2271b1;
        color: #fff;
        text-align: center;
        padding: 10px;
        font-family: monospace;
        font-size: 14px;
        z-index: 9999;
    ">
        ✅ Codespace is working! Plugin loaded from: ' . esc_html(plugin_dir_path(__FILE__)) . '
    </div>';
});

// Add a tools menu page in wp-admin
add_action('admin_menu', function () {
    add_management_page(
        'Codespace Test',
        'Codespace Test',
        'manage_options',
        'codespace-test',
        function () {
            echo '<div class="wrap">';
            echo '<h1>✅ Codespace Test</h1>';
            echo '<p>If you can see this page, the plugin is working correctly.</p>';
            echo '<table class="widefat" style="max-width:600px">';
            echo '<thead><tr><th>Check</th><th>Value</th></tr></thead>';
            echo '<tbody>';
            $checks = [
                'PHP Version'      => phpversion(),
                'WordPress Version'=> get_bloginfo('version'),
                'Plugin Directory' => plugin_dir_path(__FILE__),
                'Site URL'         => get_site_url(),
                'Database'         => defined('DB_NAME') ? DB_NAME : 'unknown',
                'WP_DEBUG'         => defined('WP_DEBUG') && WP_DEBUG ? 'true' : 'false',
            ];
            foreach ($checks as $label => $value) {
                echo "<tr><td><strong>{$label}</strong></td><td>{$value}</td></tr>";
            }
            echo '</tbody></table>';
            echo '</div>';
        }
    );
});