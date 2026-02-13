/**
 * Rodrigues & Prado Advocacia
 * Main JavaScript - Otimizado para performance
 *
 * @package RodriguesPrado
 */

(function () {
    'use strict';

    /**
     * Header scroll effect
     */
    function initHeader() {
        var header = document.getElementById('rp-header');
        if (!header) return;

        var scrollThreshold = 50;

        function handleScroll() {
            if (window.scrollY > scrollThreshold) {
                header.classList.add('scrolled');
            } else {
                header.classList.remove('scrolled');
            }
        }

        window.addEventListener('scroll', handleScroll, { passive: true });
        handleScroll();
    }

    /**
     * Mobile menu toggle
     */
    function initMobileMenu() {
        var toggle = document.getElementById('rp-menu-toggle');
        var menu = document.getElementById('rp-nav-menu');
        if (!toggle || !menu) return;

        toggle.addEventListener('click', function () {
            menu.classList.toggle('active');
            toggle.classList.toggle('active');
        });

        // Close menu on link click
        var links = menu.querySelectorAll('a');
        links.forEach(function (link) {
            link.addEventListener('click', function () {
                menu.classList.remove('active');
                toggle.classList.remove('active');
            });
        });

        // Close menu on ESC key
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && menu.classList.contains('active')) {
                menu.classList.remove('active');
                toggle.classList.remove('active');
            }
        });
    }

    /**
     * Smooth scroll for anchor links
     */
    function initSmoothScroll() {
        document.querySelectorAll('a[href^="#"]').forEach(function (link) {
            link.addEventListener('click', function (e) {
                var targetId = this.getAttribute('href');
                if (targetId === '#') return;

                var target = document.querySelector(targetId);
                if (!target) return;

                e.preventDefault();
                var headerHeight = document.getElementById('rp-header')
                    ? document.getElementById('rp-header').offsetHeight
                    : 0;

                var targetPosition = target.getBoundingClientRect().top + window.pageYOffset - headerHeight;

                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });
            });
        });
    }

    /**
     * Intersection Observer for scroll animations
     */
    function initAnimations() {
        if (!('IntersectionObserver' in window)) {
            // Fallback: show all elements
            document.querySelectorAll('.rp-animate').forEach(function (el) {
                el.classList.add('rp-visible');
            });
            return;
        }

        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.classList.add('rp-visible');
                    observer.unobserve(entry.target);
                }
            });
        }, {
            threshold: 0.1,
            rootMargin: '0px 0px -50px 0px'
        });

        document.querySelectorAll('.rp-animate').forEach(function (el) {
            observer.observe(el);
        });
    }

    /**
     * Counter animation for stats
     */
    function initCounters() {
        var counters = document.querySelectorAll('.rp-stat-number');
        if (!counters.length) return;

        if (!('IntersectionObserver' in window)) return;

        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    animateCounter(entry.target);
                    observer.unobserve(entry.target);
                }
            });
        }, { threshold: 0.5 });

        counters.forEach(function (counter) {
            observer.observe(counter);
        });
    }

    function animateCounter(element) {
        var text = element.textContent.trim();
        var hasPlus = text.includes('+');
        var hasPercent = text.includes('%');
        var numericValue = parseInt(text.replace(/[^0-9]/g, ''), 10);

        if (isNaN(numericValue)) return;

        var duration = 2000;
        var start = 0;
        var startTime = null;

        function step(timestamp) {
            if (!startTime) startTime = timestamp;
            var progress = Math.min((timestamp - startTime) / duration, 1);
            var eased = 1 - Math.pow(1 - progress, 3); // easeOutCubic
            var current = Math.floor(eased * numericValue);

            var display = current.toLocaleString('pt-BR');
            if (hasPlus) display += '+';
            if (hasPercent) display += '%';
            element.textContent = display;

            if (progress < 1) {
                requestAnimationFrame(step);
            }
        }

        requestAnimationFrame(step);
    }

    /**
     * Active navigation link highlighting
     */
    function initActiveNav() {
        var sections = document.querySelectorAll('section[id]');
        var navLinks = document.querySelectorAll('.rp-nav-menu a');

        if (!sections.length || !navLinks.length) return;

        window.addEventListener('scroll', function () {
            var scrollPos = window.scrollY + 100;

            sections.forEach(function (section) {
                var top = section.offsetTop;
                var height = section.offsetHeight;
                var id = section.getAttribute('id');

                if (scrollPos >= top && scrollPos < top + height) {
                    navLinks.forEach(function (link) {
                        link.classList.remove('active');
                        if (link.getAttribute('href') === '#' + id) {
                            link.classList.add('active');
                        }
                    });
                }
            });
        }, { passive: true });
    }

    /**
     * LGPD Cookie Notice
     */
    function initCookieNotice() {
        var notice = document.getElementById('rp-cookie-notice');
        var acceptBtn = document.getElementById('rp-cookie-accept');

        if (!notice || !acceptBtn) return;

        // Check if already accepted
        if (!localStorage.getItem('rp_cookies_accepted')) {
            notice.style.display = 'block';
        }

        acceptBtn.addEventListener('click', function () {
            localStorage.setItem('rp_cookies_accepted', 'true');
            notice.style.display = 'none';
        });
    }

    /**
     * Lazy loading for background images
     */
    function initLazyBg() {
        if (!('IntersectionObserver' in window)) return;

        var lazyBgs = document.querySelectorAll('[data-bg]');
        if (!lazyBgs.length) return;

        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (entry) {
                if (entry.isIntersecting) {
                    entry.target.style.backgroundImage = 'url(' + entry.target.dataset.bg + ')';
                    entry.target.classList.add('rp-bg-loaded');
                    observer.unobserve(entry.target);
                }
            });
        }, { rootMargin: '200px' });

        lazyBgs.forEach(function (el) {
            observer.observe(el);
        });
    }

    /**
     * Initialize all modules
     */
    function init() {
        initHeader();
        initMobileMenu();
        initSmoothScroll();
        initAnimations();
        initCounters();
        initActiveNav();
        initCookieNotice();
        initLazyBg();
    }

    // Run on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

})();
