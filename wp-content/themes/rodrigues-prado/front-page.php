<?php
/**
 * Front Page Template
 * Homepage otimizada para Elementor - Rodrigues & Prado Advocacia
 *
 * Se o Elementor estiver ativo e a pagina tiver conteudo do Elementor,
 * ele renderiza pelo Elementor. Caso contrario, renderiza o template padrao.
 *
 * @package RodriguesPrado
 */

get_header();

// Verifica se o Elementor esta gerenciando esta pagina
$elementor_active = defined( 'ELEMENTOR_VERSION' ) && \Elementor\Plugin::$instance->documents->get( get_the_ID() );

if ( $elementor_active && get_post_meta( get_the_ID(), '_elementor_edit_mode', true ) ) :
    // Renderiza conteudo do Elementor
    while ( have_posts() ) :
        the_post();
        the_content();
    endwhile;
else :
    // Template padrao da homepage (fallback sem Elementor)
    ?>

    <!-- ============================================
         HERO SECTION
         ============================================ -->
    <section class="rp-hero" id="inicio">
        <div class="rp-hero-content">
            <span class="rp-hero-badge">Rodrigues & Prado Advocacia</span>
            <h1>Excelencia Juridica com <span>Atendimento Humanizado</span></h1>
            <p>Ha mais de 15 anos defendendo seus direitos com dedicacao, etica e compromisso. Nosso escritorio oferece solucoes juridicas personalizadas para cada cliente.</p>
            <div class="rp-hero-buttons">
                <a href="https://wa.me/<?php echo esc_attr( get_theme_mod( 'rp_whatsapp', '5511999999999' ) ); ?>?text=<?php echo rawurlencode( 'Ola! Gostaria de agendar uma consulta.' ); ?>"
                   class="rp-btn rp-btn-whatsapp" target="_blank" rel="noopener noreferrer">
                    <i class="fab fa-whatsapp"></i> Agende sua Consulta
                </a>
                <a href="#areas" class="rp-btn rp-btn-outline">
                    <i class="fas fa-balance-scale"></i> Nossas Areas
                </a>
            </div>
        </div>
    </section>

    <!-- ============================================
         AREAS DE ATUACAO
         ============================================ -->
    <section class="rp-areas" id="areas">
        <div class="rp-section-title">
            <h2>Areas de Atuacao</h2>
            <p>Oferecemos assessoria juridica completa nas principais areas do Direito, sempre com foco na melhor solucao para nossos clientes.</p>
        </div>
        <div class="rp-areas-grid">
            <div class="rp-area-card rp-animate">
                <div class="rp-area-icon"><i class="fas fa-gavel"></i></div>
                <h4>Direito Civil</h4>
                <p>Contratos, responsabilidade civil, direito do consumidor, cobrancas e acoes indenizatorias.</p>
            </div>
            <div class="rp-area-card rp-animate rp-animate-delay-1">
                <div class="rp-area-icon"><i class="fas fa-briefcase"></i></div>
                <h4>Direito Trabalhista</h4>
                <p>Reclamacoes trabalhistas, rescisoes, acordos, FGTS, ferias e direitos do trabalhador.</p>
            </div>
            <div class="rp-area-card rp-animate rp-animate-delay-2">
                <div class="rp-area-icon"><i class="fas fa-shield-alt"></i></div>
                <h4>Direito Criminal</h4>
                <p>Defesa criminal, habeas corpus, recursos e acompanhamento processual em todas as instancias.</p>
            </div>
            <div class="rp-area-card rp-animate rp-animate-delay-3">
                <div class="rp-area-icon"><i class="fas fa-hand-holding-heart"></i></div>
                <h4>Direito Previdenciario</h4>
                <p>Aposentadorias, auxilio-doenca, pensao por morte, BPC/LOAS e revisoes de beneficios.</p>
            </div>
            <div class="rp-area-card rp-animate rp-animate-delay-4">
                <div class="rp-area-icon"><i class="fas fa-building"></i></div>
                <h4>Direito Empresarial</h4>
                <p>Constituicao de empresas, contratos comerciais, recuperacao judicial e societario.</p>
            </div>
            <div class="rp-area-card rp-animate rp-animate-delay-5">
                <div class="rp-area-icon"><i class="fas fa-users"></i></div>
                <h4>Direito de Familia</h4>
                <p>Divorcio, guarda de filhos, pensao alimenticia, inventario e planejamento sucessorio.</p>
            </div>
        </div>
    </section>

    <!-- ============================================
         SOBRE O ESCRITORIO
         ============================================ -->
    <section class="rp-about" id="sobre">
        <div class="rp-about-container">
            <div class="rp-about-image rp-animate">
                <img src="<?php echo esc_url( RP_THEME_URI . '/assets/images/escritorio.jpg' ); ?>"
                     alt="Escritorio Rodrigues e Prado Advocacia"
                     width="600" height="450" loading="lazy">
            </div>
            <div class="rp-about-content rp-animate rp-animate-delay-2">
                <h2>Sobre o <span>Escritorio</span></h2>
                <p>O escritorio Rodrigues & Prado Advocacia nasceu da uniao de profissionais apaixonados pelo Direito e comprometidos com a justica. Com mais de 15 anos de experiencia, construimos uma reputacao solida baseada na etica, transparencia e resultados.</p>
                <p>Nossa equipe multidisciplinar esta preparada para oferecer solucoes juridicas completas e personalizadas, sempre priorizando o atendimento humanizado e a relacao de confianca com nossos clientes.</p>
                <div class="rp-about-stats">
                    <div class="rp-stat-item">
                        <div class="rp-stat-number">15+</div>
                        <div class="rp-stat-label">Anos de Experiencia</div>
                    </div>
                    <div class="rp-stat-item">
                        <div class="rp-stat-number">2000+</div>
                        <div class="rp-stat-label">Casos Atendidos</div>
                    </div>
                    <div class="rp-stat-item">
                        <div class="rp-stat-number">98%</div>
                        <div class="rp-stat-label">Clientes Satisfeitos</div>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- ============================================
         DIFERENCIAIS
         ============================================ -->
    <section class="rp-diferenciais" id="diferenciais">
        <div class="rp-section-title">
            <h2>Por que nos escolher?</h2>
            <p>Nossos diferenciais refletem nosso compromisso com a excelencia e a satisfacao dos nossos clientes.</p>
        </div>
        <div class="rp-diff-grid">
            <div class="rp-diff-card rp-animate">
                <div class="rp-diff-icon"><i class="fas fa-user-tie"></i></div>
                <h4>Atendimento Personalizado</h4>
                <p>Cada caso e unico. Dedicamos atencao individual para entender suas necessidades e oferecer a melhor estrategia juridica.</p>
            </div>
            <div class="rp-diff-card rp-animate rp-animate-delay-1">
                <div class="rp-diff-icon"><i class="fas fa-clock"></i></div>
                <h4>Agilidade nos Processos</h4>
                <p>Trabalhamos com eficiencia para resolver suas demandas no menor tempo possivel, sem comprometer a qualidade.</p>
            </div>
            <div class="rp-diff-card rp-animate rp-animate-delay-2">
                <div class="rp-diff-icon"><i class="fas fa-handshake"></i></div>
                <h4>Transparencia Total</h4>
                <p>Mantemos voce informado em cada etapa do processo, com comunicacao clara e honesta sobre seu caso.</p>
            </div>
            <div class="rp-diff-card rp-animate rp-animate-delay-3">
                <div class="rp-diff-icon"><i class="fas fa-award"></i></div>
                <h4>Equipe Qualificada</h4>
                <p>Advogados especializados e em constante atualizacao para garantir as melhores solucoes juridicas.</p>
            </div>
        </div>
    </section>

    <!-- ============================================
         EQUIPE
         ============================================ -->
    <section class="rp-equipe" id="equipe">
        <div class="rp-section-title">
            <h2>Nossa Equipe</h2>
            <p>Profissionais dedicados e especializados prontos para defender seus direitos.</p>
        </div>
        <div class="rp-equipe-grid">
            <div class="rp-team-card rp-animate">
                <div class="rp-team-photo">
                    <img src="<?php echo esc_url( RP_THEME_URI . '/assets/images/advogado-1.jpg' ); ?>"
                         alt="Dr. Rodrigues" width="400" height="500" loading="lazy">
                    <div class="rp-team-overlay">
                        <div class="rp-social-links">
                            <a href="#" aria-label="LinkedIn"><i class="fab fa-linkedin-in"></i></a>
                            <a href="#" aria-label="E-mail"><i class="fas fa-envelope"></i></a>
                        </div>
                    </div>
                </div>
                <div class="rp-team-info">
                    <h4>Dr. Rodrigues</h4>
                    <div class="rp-team-oab">OAB/SP 000.000</div>
                    <p>Especialista em Direito Civil e Empresarial com mais de 20 anos de experiencia.</p>
                </div>
            </div>

            <div class="rp-team-card rp-animate rp-animate-delay-2">
                <div class="rp-team-photo">
                    <img src="<?php echo esc_url( RP_THEME_URI . '/assets/images/advogado-2.jpg' ); ?>"
                         alt="Dra. Prado" width="400" height="500" loading="lazy">
                    <div class="rp-team-overlay">
                        <div class="rp-social-links">
                            <a href="#" aria-label="LinkedIn"><i class="fab fa-linkedin-in"></i></a>
                            <a href="#" aria-label="E-mail"><i class="fas fa-envelope"></i></a>
                        </div>
                    </div>
                </div>
                <div class="rp-team-info">
                    <h4>Dra. Prado</h4>
                    <div class="rp-team-oab">OAB/SP 000.000</div>
                    <p>Especialista em Direito Trabalhista e Previdenciario com vasta experiencia.</p>
                </div>
            </div>

            <div class="rp-team-card rp-animate rp-animate-delay-4">
                <div class="rp-team-photo">
                    <img src="<?php echo esc_url( RP_THEME_URI . '/assets/images/advogado-3.jpg' ); ?>"
                         alt="Advogado Associado" width="400" height="500" loading="lazy">
                    <div class="rp-team-overlay">
                        <div class="rp-social-links">
                            <a href="#" aria-label="LinkedIn"><i class="fab fa-linkedin-in"></i></a>
                            <a href="#" aria-label="E-mail"><i class="fas fa-envelope"></i></a>
                        </div>
                    </div>
                </div>
                <div class="rp-team-info">
                    <h4>Dr. Associado</h4>
                    <div class="rp-team-oab">OAB/SP 000.000</div>
                    <p>Especialista em Direito Criminal e de Familia com atuacao em diversas comarcas.</p>
                </div>
            </div>
        </div>
    </section>

    <!-- ============================================
         DEPOIMENTOS
         ============================================ -->
    <section class="rp-depoimentos" id="depoimentos">
        <div class="rp-section-title">
            <h2>O que nossos clientes dizem</h2>
            <p>A satisfacao dos nossos clientes e a nossa maior recompensa.</p>
        </div>
        <div class="rp-depo-slider">
            <div class="rp-depo-card rp-animate">
                <div class="rp-depo-stars">
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                </div>
                <p>"Profissionais extremamente competentes e dedicados. Resolveram meu caso trabalhista com agilidade e transparencia. Recomendo a todos que precisam de um advogado de confianca."</p>
                <div class="rp-depo-author">
                    <div class="rp-depo-author-info">
                        <h5>Maria Silva</h5>
                        <span>Cliente - Direito Trabalhista</span>
                    </div>
                </div>
            </div>

            <div class="rp-depo-card rp-animate rp-animate-delay-2" style="margin-top: 30px;">
                <div class="rp-depo-stars">
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                </div>
                <p>"Atendimento excepcional desde o primeiro contato. Me senti acolhido e bem orientado durante todo o processo. O resultado superou minhas expectativas."</p>
                <div class="rp-depo-author">
                    <div class="rp-depo-author-info">
                        <h5>Joao Santos</h5>
                        <span>Cliente - Direito Civil</span>
                    </div>
                </div>
            </div>

            <div class="rp-depo-card rp-animate rp-animate-delay-4" style="margin-top: 30px;">
                <div class="rp-depo-stars">
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                    <i class="fas fa-star"></i>
                </div>
                <p>"Escritorio muito organizado e atencioso. Conseguiram resolver meu processo de familia com muita sensibilidade e profissionalismo. Sou muito grato pela dedicacao."</p>
                <div class="rp-depo-author">
                    <div class="rp-depo-author-info">
                        <h5>Ana Oliveira</h5>
                        <span>Cliente - Direito de Familia</span>
                    </div>
                </div>
            </div>
        </div>
    </section>

    <!-- ============================================
         CTA SECTION
         ============================================ -->
    <section class="rp-cta">
        <div class="rp-cta-content rp-animate">
            <h2>Precisa de <span>Assessoria Juridica</span>?</h2>
            <p>Entre em contato conosco e agende uma consulta. Estamos prontos para ajudar voce a encontrar a melhor solucao para o seu caso.</p>
            <a href="tel:<?php echo esc_attr( preg_replace( '/[^0-9+]/', '', get_theme_mod( 'rp_phone', '(11) 3000-0000' ) ) ); ?>"
               class="rp-cta-phone">
                <i class="fas fa-phone-alt"></i> <?php echo esc_html( get_theme_mod( 'rp_phone', '(11) 3000-0000' ) ); ?>
            </a>
            <div class="rp-hero-buttons">
                <a href="https://wa.me/<?php echo esc_attr( get_theme_mod( 'rp_whatsapp', '5511999999999' ) ); ?>?text=<?php echo rawurlencode( 'Ola! Gostaria de agendar uma consulta.' ); ?>"
                   class="rp-btn rp-btn-whatsapp" target="_blank" rel="noopener noreferrer">
                    <i class="fab fa-whatsapp"></i> WhatsApp
                </a>
                <a href="mailto:<?php echo esc_attr( get_theme_mod( 'rp_email', 'contato@rodrigueseprado.com.br' ) ); ?>"
                   class="rp-btn rp-btn-outline">
                    <i class="fas fa-envelope"></i> E-mail
                </a>
            </div>
        </div>
    </section>

    <?php
endif;

get_footer();
