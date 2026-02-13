<?php
/**
 * The template for displaying all pages
 *
 * @package RodriguesPrado
 */

get_header();
?>

<main id="primary" class="site-main">
    <?php
    while ( have_posts() ) :
        the_post();
        ?>
        <article id="post-<?php the_ID(); ?>" <?php post_class(); ?>>
            <?php if ( ! function_exists( 'elementor_theme_do_location' ) || ! elementor_theme_do_location( 'single' ) ) : ?>
                <header class="entry-header" style="padding: 120px 20px 40px; background: var(--rp-primary); text-align: center;">
                    <div style="max-width: 1200px; margin: 0 auto;">
                        <?php the_title( '<h1 class="entry-title" style="color: #fff;">', '</h1>' ); ?>
                    </div>
                </header>

                <div class="entry-content" style="max-width: 900px; margin: 0 auto; padding: 60px 20px;">
                    <?php the_content(); ?>
                </div>
            <?php endif; ?>
        </article>
        <?php
    endwhile;
    ?>
</main>

<?php
get_footer();
