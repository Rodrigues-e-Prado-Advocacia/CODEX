<?php
/**
 * The template for displaying 404 pages (not found)
 *
 * @package RodriguesPrado
 */

get_header();
?>

<main id="primary" class="site-main">
    <section class="rp-hero" style="min-height: 80vh;">
        <div class="rp-hero-content">
            <h1 style="color: #fff;">404</h1>
            <p style="color: rgba(255,255,255,0.8); font-size: 1.3rem;">Pagina nao encontrada</p>
            <p style="color: rgba(255,255,255,0.6);">A pagina que voce procura nao existe ou foi removida.</p>
            <div class="rp-hero-buttons" style="margin-top: 30px;">
                <a href="<?php echo esc_url( home_url( '/' ) ); ?>" class="rp-btn rp-btn-primary">
                    <i class="fas fa-home"></i> Voltar ao Inicio
                </a>
                <a href="https://wa.me/<?php echo esc_attr( get_theme_mod( 'rp_whatsapp', '5511999999999' ) ); ?>"
                   class="rp-btn rp-btn-whatsapp" target="_blank" rel="noopener noreferrer">
                    <i class="fab fa-whatsapp"></i> Fale Conosco
                </a>
            </div>
        </div>
    </section>
</main>

<?php
get_footer();
