<!-- Footer -->
<footer class="rp-footer" id="contato">
    <div class="rp-footer-grid">
        <!-- Coluna 1: Sobre -->
        <div class="rp-footer-col">
            <div class="rp-footer-logo">
                <?php if ( has_custom_logo() ) : ?>
                    <?php the_custom_logo(); ?>
                <?php else : ?>
                    <img src="<?php echo esc_url( get_template_directory_uri() . '/assets/images/logo-white.png' ); ?>"
                         alt="<?php bloginfo( 'name' ); ?>"
                         width="180" height="45" loading="lazy">
                <?php endif; ?>
            </div>
            <p>Escritorio de advocacia comprometido com a excelencia juridica e o atendimento humanizado. Sua confianca e nosso maior patrimonio.</p>
            <div class="rp-footer-social">
                <?php
                $social_links = array(
                    'instagram' => 'fab fa-instagram',
                    'facebook'  => 'fab fa-facebook-f',
                    'linkedin'  => 'fab fa-linkedin-in',
                );
                foreach ( $social_links as $network => $icon ) :
                    $url = get_theme_mod( 'rp_social_' . $network, '' );
                    if ( $url ) :
                        ?>
                        <a href="<?php echo esc_url( $url ); ?>" target="_blank" rel="noopener noreferrer"
                           aria-label="<?php echo esc_attr( ucfirst( $network ) ); ?>">
                            <i class="<?php echo esc_attr( $icon ); ?>"></i>
                        </a>
                        <?php
                    endif;
                endforeach;

                // Defaults if no social media configured
                if ( ! get_theme_mod( 'rp_social_instagram' ) && ! get_theme_mod( 'rp_social_facebook' ) ) :
                    ?>
                    <a href="#" aria-label="Instagram"><i class="fab fa-instagram"></i></a>
                    <a href="#" aria-label="Facebook"><i class="fab fa-facebook-f"></i></a>
                    <a href="#" aria-label="LinkedIn"><i class="fab fa-linkedin-in"></i></a>
                <?php endif; ?>
            </div>
        </div>

        <!-- Coluna 2: Links Rapidos -->
        <div class="rp-footer-col">
            <h5>Links Rapidos</h5>
            <ul>
                <li><a href="#inicio"><i class="fas fa-chevron-right"></i> Inicio</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Areas de Atuacao</a></li>
                <li><a href="#sobre"><i class="fas fa-chevron-right"></i> O Escritorio</a></li>
                <li><a href="#equipe"><i class="fas fa-chevron-right"></i> Equipe</a></li>
                <li><a href="#depoimentos"><i class="fas fa-chevron-right"></i> Depoimentos</a></li>
            </ul>
        </div>

        <!-- Coluna 3: Areas de Atuacao -->
        <div class="rp-footer-col">
            <h5>Areas de Atuacao</h5>
            <ul>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito Civil</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito Trabalhista</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito Criminal</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito Previdenciario</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito Empresarial</a></li>
                <li><a href="#areas"><i class="fas fa-chevron-right"></i> Direito de Familia</a></li>
            </ul>
        </div>

        <!-- Coluna 4: Contato -->
        <div class="rp-footer-col">
            <h5>Contato</h5>
            <div class="rp-footer-contact-item">
                <i class="fas fa-map-marker-alt"></i>
                <span><?php echo esc_html( get_theme_mod( 'rp_address', 'Av. Paulista, 1000 - Sala 100, Bela Vista, Sao Paulo - SP, 01310-100' ) ); ?></span>
            </div>
            <div class="rp-footer-contact-item">
                <i class="fas fa-phone-alt"></i>
                <a href="tel:<?php echo esc_attr( preg_replace( '/[^0-9+]/', '', get_theme_mod( 'rp_phone', '(11) 3000-0000' ) ) ); ?>">
                    <?php echo esc_html( get_theme_mod( 'rp_phone', '(11) 3000-0000' ) ); ?>
                </a>
            </div>
            <div class="rp-footer-contact-item">
                <i class="fab fa-whatsapp"></i>
                <a href="https://wa.me/<?php echo esc_attr( get_theme_mod( 'rp_whatsapp', '5511999999999' ) ); ?>?text=<?php echo rawurlencode( 'Ola! Gostaria de agendar uma consulta.' ); ?>"
                   target="_blank" rel="noopener noreferrer">
                    WhatsApp
                </a>
            </div>
            <div class="rp-footer-contact-item">
                <i class="fas fa-envelope"></i>
                <a href="mailto:<?php echo esc_attr( get_theme_mod( 'rp_email', 'contato@rodrigueseprado.com.br' ) ); ?>">
                    <?php echo esc_html( get_theme_mod( 'rp_email', 'contato@rodrigueseprado.com.br' ) ); ?>
                </a>
            </div>
            <div class="rp-footer-contact-item">
                <i class="fas fa-clock"></i>
                <span>Seg - Sex: 08h as 18h</span>
            </div>
        </div>
    </div>

    <div class="rp-footer-bottom">
        <p>&copy; <?php echo esc_html( date( 'Y' ) ); ?> <?php bloginfo( 'name' ); ?>. Todos os direitos reservados. | Desenvolvido com excelencia.</p>
    </div>
</footer>

<!-- WhatsApp Floating Button -->
<a href="https://wa.me/<?php echo esc_attr( get_theme_mod( 'rp_whatsapp', '5511999999999' ) ); ?>?text=<?php echo rawurlencode( 'Ola! Gostaria de agendar uma consulta.' ); ?>"
   class="rp-whatsapp-float"
   target="_blank"
   rel="noopener noreferrer"
   aria-label="Fale conosco pelo WhatsApp">
    <i class="fab fa-whatsapp"></i>
</a>

<?php wp_footer(); ?>
</body>
</html>
