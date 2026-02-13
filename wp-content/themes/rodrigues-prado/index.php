<?php
/**
 * The main template file
 *
 * @package RodriguesPrado
 */

get_header();
?>

<main id="primary" class="site-main">
    <?php
    if ( have_posts() ) :
        while ( have_posts() ) :
            the_post();
            the_content();
        endwhile;
    else :
        echo '<div class="rp-no-content"><p>' . esc_html__( 'Nenhum conteudo encontrado.', 'rodrigues-prado' ) . '</p></div>';
    endif;
    ?>
</main>

<?php
get_footer();
