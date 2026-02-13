<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo( 'charset' ); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>

<!-- Header / Navegacao Principal -->
<header class="rp-header" id="rp-header">
    <div class="rp-nav-container">
        <div class="rp-logo">
            <?php if ( has_custom_logo() ) : ?>
                <?php the_custom_logo(); ?>
            <?php else : ?>
                <a href="<?php echo esc_url( home_url( '/' ) ); ?>">
                    <img src="<?php echo esc_url( get_template_directory_uri() . '/assets/images/logo-white.png' ); ?>"
                         alt="<?php bloginfo( 'name' ); ?>"
                         width="200" height="50"
                         loading="eager">
                </a>
            <?php endif; ?>
        </div>

        <div class="rp-menu-toggle" id="rp-menu-toggle" aria-label="Menu" role="button" tabindex="0">
            <span></span>
            <span></span>
            <span></span>
        </div>

        <nav aria-label="<?php esc_attr_e( 'Navegacao principal', 'rodrigues-prado' ); ?>">
            <?php if ( has_nav_menu( 'primary' ) ) : ?>
                <?php
                wp_nav_menu( array(
                    'theme_location' => 'primary',
                    'menu_class'     => 'rp-nav-menu',
                    'container'      => false,
                    'fallback_cb'    => false,
                    'depth'          => 1,
                ) );
                ?>
            <?php else : ?>
                <ul class="rp-nav-menu" id="rp-nav-menu">
                    <li><a href="#inicio">Inicio</a></li>
                    <li><a href="#areas">Areas de Atuacao</a></li>
                    <li><a href="#sobre">O Escritorio</a></li>
                    <li><a href="#equipe">Equipe</a></li>
                    <li><a href="#depoimentos">Depoimentos</a></li>
                    <li><a href="#contato" class="rp-nav-cta">Contato</a></li>
                </ul>
            <?php endif; ?>
        </nav>
    </div>
</header>
