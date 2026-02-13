<?php
/**
 * Elementor Setup & Configuration
 * Configuracoes otimizadas para o Elementor
 *
 * @package RodriguesPrado
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * Set Elementor default settings on theme activation
 */
function rp_set_elementor_defaults() {
    // Only run if Elementor is active
    if ( ! defined( 'ELEMENTOR_VERSION' ) ) {
        return;
    }

    // Set default color scheme
    update_option( 'elementor_scheme_color', array(
        '1' => '#1B2A4A',
        '2' => '#C9A84C',
        '3' => '#2D2D2D',
        '4' => '#6B6B6B',
    ) );

    // Set default fonts
    update_option( 'elementor_scheme_typography', array(
        '1' => array(
            'font_family' => 'Playfair Display',
            'font_weight' => '700',
        ),
        '2' => array(
            'font_family' => 'Playfair Display',
            'font_weight' => '600',
        ),
        '3' => array(
            'font_family' => 'Montserrat',
            'font_weight' => '400',
        ),
        '4' => array(
            'font_family' => 'Montserrat',
            'font_weight' => '500',
        ),
    ) );

    // Set default container width
    update_option( 'elementor_container_width', 1200 );

    // Enable stretched section
    update_option( 'elementor_stretched_section_container', '' );

    // Disable default colors/fonts to use theme's
    update_option( 'elementor_disable_color_schemes', 'yes' );
    update_option( 'elementor_disable_typography_schemes', 'yes' );

    // Set default generic fonts
    update_option( 'elementor_default_generic_fonts', 'Sans-serif' );

    // Enable lightbox
    update_option( 'elementor_global_image_lightbox', 'yes' );

    // Set page title selector
    update_option( 'elementor_page_title_selector', 'h1.entry-title' );

    // Viewport meta tag
    update_option( 'elementor_viewport_lg', 1025 );
    update_option( 'elementor_viewport_md', 768 );
}
add_action( 'after_switch_theme', 'rp_set_elementor_defaults' );

/**
 * Add Elementor support for custom post types
 */
function rp_elementor_post_types( $post_types ) {
    $post_types[] = 'page';
    return array_unique( $post_types );
}
add_filter( 'elementor/utils/get_public_post_types', 'rp_elementor_post_types' );

/**
 * Register custom Elementor categories
 */
function rp_register_elementor_categories( $elements_manager ) {
    $elements_manager->add_category(
        'rodrigues-prado',
        array(
            'title' => __( 'Rodrigues & Prado', 'rodrigues-prado' ),
            'icon'  => 'fa fa-balance-scale',
        )
    );
}
add_action( 'elementor/elements/categories_registered', 'rp_register_elementor_categories' );

/**
 * Add custom fonts to Elementor
 */
function rp_elementor_custom_fonts( $fonts ) {
    $fonts['Playfair Display'] = 'googlefonts';
    $fonts['Montserrat']       = 'googlefonts';
    return $fonts;
}
add_filter( 'elementor/fonts/additional_fonts', 'rp_elementor_custom_fonts' );

/**
 * Enqueue Elementor editor custom styles
 */
function rp_elementor_editor_styles() {
    wp_enqueue_style(
        'rp-elementor-editor',
        RP_THEME_URI . '/assets/css/elementor-custom.css',
        array(),
        RP_THEME_VERSION
    );
}
add_action( 'elementor/editor/after_enqueue_styles', 'rp_elementor_editor_styles' );

/**
 * Import Elementor template on theme activation
 * Creates the homepage with Elementor content
 */
function rp_create_elementor_homepage() {
    // Check if homepage already exists
    $existing = get_page_by_title( 'Home' );
    if ( $existing ) {
        return;
    }

    // Create the homepage
    $homepage_id = wp_insert_post( array(
        'post_title'   => 'Home',
        'post_content' => '',
        'post_status'  => 'publish',
        'post_type'    => 'page',
        'meta_input'   => array(
            '_wp_page_template'  => 'elementor_header_footer',
            '_elementor_edit_mode' => 'builder',
            '_elementor_template_type' => 'wp-page',
        ),
    ) );

    if ( $homepage_id && ! is_wp_error( $homepage_id ) ) {
        // Set as front page
        update_option( 'page_on_front', $homepage_id );
        update_option( 'show_on_front', 'page' );

        // Load Elementor template data
        $template_file = RP_THEME_DIR . '/elementor-templates/homepage.json';
        if ( file_exists( $template_file ) ) {
            $template_content = file_get_contents( $template_file );
            $template_data = json_decode( $template_content, true );

            if ( $template_data && isset( $template_data['content'] ) ) {
                update_post_meta( $homepage_id, '_elementor_data', wp_slash( wp_json_encode( $template_data['content'] ) ) );

                if ( isset( $template_data['page_settings'] ) ) {
                    update_post_meta( $homepage_id, '_elementor_page_settings', $template_data['page_settings'] );
                }
            }
        }
    }

    // Create Privacy Policy page (LGPD)
    $privacy = get_page_by_title( 'Politica de Privacidade' );
    if ( ! $privacy ) {
        $privacy_id = wp_insert_post( array(
            'post_title'   => 'Politica de Privacidade',
            'post_content' => rp_get_privacy_policy_content(),
            'post_status'  => 'publish',
            'post_type'    => 'page',
        ) );

        if ( $privacy_id && ! is_wp_error( $privacy_id ) ) {
            update_option( 'wp_page_for_privacy_policy', $privacy_id );
        }
    }
}
add_action( 'after_switch_theme', 'rp_create_elementor_homepage' );

/**
 * Default Privacy Policy content (LGPD)
 */
function rp_get_privacy_policy_content() {
    return '
<h2>Politica de Privacidade</h2>
<p>O escritorio Rodrigues &amp; Prado Advocacia esta comprometido com a protecao dos dados pessoais de seus clientes e visitantes, em conformidade com a Lei Geral de Protecao de Dados (LGPD - Lei n. 13.709/2018).</p>

<h3>1. Dados Coletados</h3>
<p>Coletamos apenas os dados necessarios para a prestacao de nossos servicos juridicos, incluindo: nome, e-mail, telefone e informacoes relacionadas ao caso juridico.</p>

<h3>2. Finalidade</h3>
<p>Os dados sao utilizados exclusivamente para: atendimento juridico, comunicacao com clientes, e cumprimento de obrigacoes legais.</p>

<h3>3. Compartilhamento</h3>
<p>Seus dados nao serao compartilhados com terceiros, exceto quando necessario para a prestacao dos servicos juridicos ou por determinacao legal.</p>

<h3>4. Seguranca</h3>
<p>Adotamos medidas de seguranca adequadas para proteger seus dados pessoais contra acesso nao autorizado, uso indevido ou divulgacao.</p>

<h3>5. Seus Direitos</h3>
<p>Voce tem direito a: acessar, corrigir, eliminar seus dados pessoais, bem como revogar seu consentimento a qualquer momento.</p>

<h3>6. Contato</h3>
<p>Para exercer seus direitos ou esclarecer duvidas sobre esta politica, entre em contato conosco.</p>
';
}

/**
 * Admin notice: Elementor not installed
 */
function rp_elementor_notice() {
    if ( defined( 'ELEMENTOR_VERSION' ) ) {
        return;
    }

    $screen = get_current_screen();
    if ( ! $screen || 'themes' !== $screen->id ) {
        return;
    }
    ?>
    <div class="notice notice-warning is-dismissible">
        <p>
            <strong>Rodrigues &amp; Prado Advocacia:</strong>
            Este tema foi otimizado para funcionar com o <strong>Elementor Page Builder</strong>.
            <a href="<?php echo esc_url( admin_url( 'plugin-install.php?s=elementor&tab=search&type=term' ) ); ?>">
                Instalar Elementor
            </a>
        </p>
    </div>
    <?php
}
add_action( 'admin_notices', 'rp_elementor_notice' );
