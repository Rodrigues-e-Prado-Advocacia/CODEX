<?php
/**
 * Rodrigues & Prado Advocacia - Theme Functions
 * Tema otimizado para Elementor
 *
 * @package RodriguesPrado
 * @version 1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

define( 'RP_THEME_VERSION', '1.0.0' );
define( 'RP_THEME_DIR', get_template_directory() );
define( 'RP_THEME_URI', get_template_directory_uri() );

/**
 * Theme Setup
 */
function rp_theme_setup() {
    // Suporte a traducao
    load_theme_textdomain( 'rodrigues-prado', RP_THEME_DIR . '/languages' );

    // Suporte ao Elementor
    add_theme_support( 'elementor' );
    add_theme_support( 'elementor-default-template' );

    // Suporte basico do WordPress
    add_theme_support( 'title-tag' );
    add_theme_support( 'post-thumbnails' );
    add_theme_support( 'custom-logo', array(
        'height'      => 80,
        'width'       => 250,
        'flex-height' => true,
        'flex-width'  => true,
    ) );
    add_theme_support( 'html5', array(
        'search-form',
        'comment-form',
        'comment-list',
        'gallery',
        'caption',
        'style',
        'script',
    ) );
    add_theme_support( 'responsive-embeds' );
    add_theme_support( 'align-wide' );
    add_theme_support( 'wp-block-styles' );

    // Menus de navegacao
    register_nav_menus( array(
        'primary'   => __( 'Menu Principal', 'rodrigues-prado' ),
        'footer'    => __( 'Menu Rodape', 'rodrigues-prado' ),
    ) );

    // Tamanhos de imagem otimizados
    add_image_size( 'rp-hero', 1920, 1080, true );
    add_image_size( 'rp-team', 400, 500, true );
    add_image_size( 'rp-card', 600, 400, true );
    add_image_size( 'rp-thumb', 300, 300, true );
}
add_action( 'after_setup_theme', 'rp_theme_setup' );

/**
 * Enqueue Scripts & Styles - Otimizado para performance
 */
function rp_enqueue_assets() {
    // Google Fonts - Preconnect para performance
    wp_enqueue_style(
        'rp-google-fonts-preconnect',
        'https://fonts.googleapis.com',
        array(),
        null
    );

    wp_enqueue_style(
        'rp-google-fonts',
        'https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;600;700;800&family=Montserrat:wght@300;400;500;600;700&display=swap',
        array(),
        null
    );

    // Font Awesome (icons)
    wp_enqueue_style(
        'rp-fontawesome',
        'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css',
        array(),
        '6.5.1'
    );

    // Theme Stylesheet
    wp_enqueue_style(
        'rp-theme-style',
        get_stylesheet_uri(),
        array(),
        RP_THEME_VERSION
    );

    // Custom Elementor Styles
    wp_enqueue_style(
        'rp-elementor-custom',
        RP_THEME_URI . '/assets/css/elementor-custom.css',
        array( 'rp-theme-style' ),
        RP_THEME_VERSION
    );

    // Main JavaScript
    wp_enqueue_script(
        'rp-main-js',
        RP_THEME_URI . '/assets/js/main.js',
        array(),
        RP_THEME_VERSION,
        true
    );

    // Localize script
    wp_localize_script( 'rp-main-js', 'rpData', array(
        'ajaxUrl'  => admin_url( 'admin-ajax.php' ),
        'nonce'    => wp_create_nonce( 'rp_nonce' ),
        'themeUrl' => RP_THEME_URI,
    ) );
}
add_action( 'wp_enqueue_scripts', 'rp_enqueue_assets' );

/**
 * Preload de recursos criticos
 */
function rp_preload_resources() {
    echo '<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>' . "\n";
    echo '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' . "\n";
    echo '<link rel="preconnect" href="https://cdnjs.cloudflare.com" crossorigin>' . "\n";
    echo '<link rel="dns-prefetch" href="//fonts.googleapis.com">' . "\n";
    echo '<link rel="dns-prefetch" href="//cdnjs.cloudflare.com">' . "\n";
}
add_action( 'wp_head', 'rp_preload_resources', 1 );

/**
 * Otimizacoes de performance
 */
function rp_performance_optimizations() {
    // Remove emojis do WordPress (melhora performance)
    remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
    remove_action( 'wp_print_styles', 'print_emoji_styles' );
    remove_action( 'admin_print_scripts', 'print_emoji_detection_script' );
    remove_action( 'admin_print_styles', 'print_emoji_styles' );

    // Remove meta tags desnecessarias
    remove_action( 'wp_head', 'wp_generator' );
    remove_action( 'wp_head', 'wlwmanifest_link' );
    remove_action( 'wp_head', 'rsd_link' );
    remove_action( 'wp_head', 'wp_shortlink_wp_head' );

    // Remove oEmbed
    remove_action( 'wp_head', 'wp_oembed_add_discovery_links' );
}
add_action( 'init', 'rp_performance_optimizations' );

/**
 * Add async/defer to scripts para melhor carregamento
 */
function rp_script_loader_tag( $tag, $handle, $src ) {
    $async_scripts = array( 'rp-fontawesome' );
    $defer_scripts = array( 'rp-main-js' );

    if ( in_array( $handle, $defer_scripts, true ) ) {
        return str_replace( ' src', ' defer src', $tag );
    }

    return $tag;
}
add_filter( 'script_loader_tag', 'rp_script_loader_tag', 10, 3 );

/**
 * Configuracoes do Elementor
 */
function rp_elementor_defaults( $manager ) {
    // Define cores padrao do Elementor
    $manager->get_scheme( 'color' )->save_scheme( array(
        '1' => '#1B2A4A', // Primary
        '2' => '#C9A84C', // Secondary
        '3' => '#2D2D2D', // Text
        '4' => '#6B6B6B', // Accent
    ) );
}

/**
 * Registrar Elementor Widget Locations
 */
function rp_register_elementor_locations( $elementor_theme_manager ) {
    $elementor_theme_manager->register_all_core_location();
}
add_action( 'elementor/theme/register_locations', 'rp_register_elementor_locations' );

/**
 * Customizer Settings
 */
function rp_customize_register( $wp_customize ) {
    // Secao: Informacoes do Escritorio
    $wp_customize->add_section( 'rp_office_info', array(
        'title'    => __( 'Informacoes do Escritorio', 'rodrigues-prado' ),
        'priority' => 30,
    ) );

    // WhatsApp Number
    $wp_customize->add_setting( 'rp_whatsapp', array(
        'default'           => '5511999999999',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'rp_whatsapp', array(
        'label'   => __( 'Numero do WhatsApp (com DDI)', 'rodrigues-prado' ),
        'section' => 'rp_office_info',
        'type'    => 'text',
    ) );

    // Phone Number
    $wp_customize->add_setting( 'rp_phone', array(
        'default'           => '(11) 3000-0000',
        'sanitize_callback' => 'sanitize_text_field',
    ) );
    $wp_customize->add_control( 'rp_phone', array(
        'label'   => __( 'Telefone do Escritorio', 'rodrigues-prado' ),
        'section' => 'rp_office_info',
        'type'    => 'text',
    ) );

    // Email
    $wp_customize->add_setting( 'rp_email', array(
        'default'           => 'contato@rodrigueseprado.com.br',
        'sanitize_callback' => 'sanitize_email',
    ) );
    $wp_customize->add_control( 'rp_email', array(
        'label'   => __( 'E-mail do Escritorio', 'rodrigues-prado' ),
        'section' => 'rp_office_info',
        'type'    => 'email',
    ) );

    // Address
    $wp_customize->add_setting( 'rp_address', array(
        'default'           => '',
        'sanitize_callback' => 'sanitize_textarea_field',
    ) );
    $wp_customize->add_control( 'rp_address', array(
        'label'   => __( 'Endereco do Escritorio', 'rodrigues-prado' ),
        'section' => 'rp_office_info',
        'type'    => 'textarea',
    ) );

    // Google Maps Embed URL
    $wp_customize->add_setting( 'rp_maps_url', array(
        'default'           => '',
        'sanitize_callback' => 'esc_url_raw',
    ) );
    $wp_customize->add_control( 'rp_maps_url', array(
        'label'   => __( 'URL do Google Maps Embed', 'rodrigues-prado' ),
        'section' => 'rp_office_info',
        'type'    => 'url',
    ) );

    // Social Media
    $wp_customize->add_section( 'rp_social', array(
        'title'    => __( 'Redes Sociais', 'rodrigues-prado' ),
        'priority' => 35,
    ) );

    $social_networks = array(
        'instagram' => 'Instagram URL',
        'facebook'  => 'Facebook URL',
        'linkedin'  => 'LinkedIn URL',
    );

    foreach ( $social_networks as $network => $label ) {
        $wp_customize->add_setting( 'rp_social_' . $network, array(
            'default'           => '',
            'sanitize_callback' => 'esc_url_raw',
        ) );
        $wp_customize->add_control( 'rp_social_' . $network, array(
            'label'   => $label,
            'section' => 'rp_social',
            'type'    => 'url',
        ) );
    }
}
add_action( 'customize_register', 'rp_customize_register' );

/**
 * Schema.org Structured Data para SEO
 */
function rp_schema_markup() {
    if ( ! is_front_page() ) {
        return;
    }

    $schema = array(
        '@context'    => 'https://schema.org',
        '@type'       => 'LegalService',
        'name'        => 'Rodrigues & Prado Advocacia',
        'description' => 'Escritorio de advocacia especializado em Direito Civil, Trabalhista, Criminal, Previdenciario, Empresarial e de Familia.',
        'url'         => home_url(),
        'logo'        => RP_THEME_URI . '/assets/images/logo.png',
        'telephone'   => get_theme_mod( 'rp_phone', '(11) 3000-0000' ),
        'email'       => get_theme_mod( 'rp_email', 'contato@rodrigueseprado.com.br' ),
        'address'     => array(
            '@type'           => 'PostalAddress',
            'addressLocality' => 'Sao Paulo',
            'addressRegion'   => 'SP',
            'addressCountry'  => 'BR',
        ),
        'priceRange'  => '$$',
        'openingHours' => 'Mo-Fr 08:00-18:00',
        'sameAs'       => array_filter( array(
            get_theme_mod( 'rp_social_instagram', '' ),
            get_theme_mod( 'rp_social_facebook', '' ),
            get_theme_mod( 'rp_social_linkedin', '' ),
        ) ),
    );

    echo '<script type="application/ld+json">' . wp_json_encode( $schema, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE ) . '</script>' . "\n";
}
add_action( 'wp_head', 'rp_schema_markup' );

/**
 * Meta tags SEO para a homepage
 */
function rp_seo_meta_tags() {
    if ( ! is_front_page() ) {
        return;
    }
    ?>
    <meta name="description" content="Rodrigues &amp; Prado Advocacia - Escritorio de advocacia com atendimento humanizado e personalizado. Especialistas em Direito Civil, Trabalhista, Criminal e mais.">
    <meta name="keywords" content="advocacia, advogado, escritorio de advocacia, direito civil, direito trabalhista, direito criminal, Rodrigues Prado">
    <meta property="og:title" content="Rodrigues &amp; Prado Advocacia - Excelencia Juridica">
    <meta property="og:description" content="Escritorio de advocacia com atendimento humanizado. Mais de 15 anos de experiencia em diversas areas do Direito.">
    <meta property="og:type" content="website">
    <meta property="og:url" content="<?php echo esc_url( home_url() ); ?>">
    <meta property="og:image" content="<?php echo esc_url( RP_THEME_URI . '/assets/images/og-image.jpg' ); ?>">
    <meta property="og:locale" content="pt_BR">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="robots" content="index, follow">
    <?php
}
add_action( 'wp_head', 'rp_seo_meta_tags', 5 );

/**
 * Widgets
 */
function rp_widgets_init() {
    register_sidebar( array(
        'name'          => __( 'Footer Widget 1', 'rodrigues-prado' ),
        'id'            => 'footer-1',
        'before_widget' => '<div class="rp-footer-widget">',
        'after_widget'  => '</div>',
        'before_title'  => '<h5>',
        'after_title'   => '</h5>',
    ) );

    register_sidebar( array(
        'name'          => __( 'Footer Widget 2', 'rodrigues-prado' ),
        'id'            => 'footer-2',
        'before_widget' => '<div class="rp-footer-widget">',
        'after_widget'  => '</div>',
        'before_title'  => '<h5>',
        'after_title'   => '</h5>',
    ) );
}
add_action( 'widgets_init', 'rp_widgets_init' );

/**
 * LGPD Cookie Notice Helper
 */
function rp_cookie_notice() {
    ?>
    <div id="rp-cookie-notice" class="rp-cookie-notice" style="display:none;">
        <div class="rp-cookie-content">
            <p>Este site utiliza cookies para melhorar sua experiencia. Ao continuar navegando, voce concorda com a nossa
            <a href="<?php echo esc_url( get_privacy_policy_url() ); ?>">Politica de Privacidade</a>.</p>
            <button id="rp-cookie-accept" class="rp-btn rp-btn-primary">Aceitar</button>
        </div>
    </div>
    <?php
}
add_action( 'wp_footer', 'rp_cookie_notice' );

/**
 * Disable Gutenberg on Elementor pages
 */
function rp_disable_gutenberg_on_elementor( $use_block_editor, $post ) {
    if ( get_post_meta( $post->ID, '_elementor_edit_mode', true ) === 'builder' ) {
        return false;
    }
    return $use_block_editor;
}
add_filter( 'use_block_editor_for_post', 'rp_disable_gutenberg_on_elementor', 10, 2 );

/**
 * Include Elementor setup and configuration
 */
require_once RP_THEME_DIR . '/inc/elementor-setup.php';
