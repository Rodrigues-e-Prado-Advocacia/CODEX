# Rodrigues & Prado Advocacia - Guia de Instalacao

## Tema WordPress Otimizado para Elementor

### Requisitos

- WordPress 6.0 ou superior
- PHP 7.4 ou superior
- Plugin Elementor (gratuito) instalado e ativo
- Plugin Elementor Pro (opcional, para funcionalidades avancadas)

---

### 1. Instalacao do Tema

1. Acesse o painel WordPress: **Aparencia > Temas > Adicionar Novo > Enviar Tema**
2. Faca upload da pasta `wp-content/themes/rodrigues-prado` como ZIP
3. Clique em **Ativar**

Ou via FTP:
1. Copie a pasta `rodrigues-prado` para `wp-content/themes/`
2. No painel WordPress, va em **Aparencia > Temas** e ative o tema

### 2. Instalar o Elementor

1. Va em **Plugins > Adicionar Novo**
2. Pesquise por **"Elementor"**
3. Instale e ative o **Elementor Website Builder**

### 3. Configurar a Homepage

Ao ativar o tema, a homepage sera criada automaticamente. Se nao:

1. Va em **Paginas > Adicionar Nova**
2. Titulo: "Home"
3. No atributo da pagina, selecione o template **"Elementor Full Width"**
4. Clique em **"Editar com Elementor"**
5. Importe o template: clique no icone de pasta > **Importar Template**
6. Selecione o arquivo `elementor-templates/homepage.json`

**Definir como pagina inicial:**
1. Va em **Configuracoes > Leitura**
2. Selecione "Uma pagina estatica"
3. Em "Pagina inicial", selecione "Home"

### 4. Configurar o Menu de Navegacao

1. Va em **Aparencia > Menus**
2. Crie um novo menu chamado "Menu Principal"
3. Adicione links personalizados com ancoras:
   - Inicio: `#inicio`
   - Areas de Atuacao: `#areas`
   - O Escritorio: `#sobre`
   - Equipe: `#equipe`
   - Depoimentos: `#depoimentos`
   - Contato: `#contato`
4. Marque "Menu Principal" como localizacao
5. Salve

### 5. Configurar Informacoes do Escritorio

1. Va em **Aparencia > Personalizar**
2. Na secao **"Informacoes do Escritorio"**, configure:
   - Numero do WhatsApp (com DDI: 5511999999999)
   - Telefone do Escritorio
   - E-mail do Escritorio
   - Endereco completo
   - URL do Google Maps Embed
3. Na secao **"Redes Sociais"**, adicione:
   - URL do Instagram
   - URL do Facebook
   - URL do LinkedIn
4. Na secao **"Identidade do Site"**, faca upload do logo

### 6. Imagens Necessarias

Substitua as imagens placeholder na pasta `assets/images/`:

| Arquivo | Dimensao Recomendada | Descricao |
|---------|---------------------|-----------|
| `logo-white.png` | 250x80px | Logo branco (header/footer) |
| `hero-bg.jpg` | 1920x1080px | Imagem de fundo do hero |
| `escritorio.jpg` | 600x450px | Foto do escritorio |
| `advogado-1.jpg` | 400x500px | Foto Dr. Rodrigues |
| `advogado-2.jpg` | 400x500px | Foto Dra. Prado |
| `advogado-3.jpg` | 400x500px | Foto advogado associado |
| `og-image.jpg` | 1200x630px | Imagem para compartilhamento em redes sociais |

### 7. SEO e Performance

O tema ja inclui:

- **Schema.org** markup (LegalService) para Google
- **Open Graph** meta tags para redes sociais
- **Preconnect** e **DNS Prefetch** para fontes
- **Lazy loading** nativo para imagens
- **Minificacao** de CSS/JS em producao
- **LGPD** Cookie notice integrado
- **Politica de Privacidade** pagina criada automaticamente

**Plugins recomendados para SEO:**
- Yoast SEO ou Rank Math
- WP Super Cache ou W3 Total Cache
- Imagify ou ShortPixel (otimizacao de imagens)
- WP Rocket (cache premium)

---

### Estrutura do Tema

```
rodrigues-prado/
├── style.css                  # Estilos principais do tema
├── functions.php              # Funcoes do tema
├── header.php                 # Cabecalho com navegacao
├── footer.php                 # Rodape com contato e WhatsApp
├── front-page.php             # Template da homepage (com fallback)
├── page.php                   # Template de paginas
├── index.php                  # Template padrao
├── 404.php                    # Pagina de erro 404
├── screenshot.svg             # Preview do tema
├── inc/
│   └── elementor-setup.php    # Configuracao do Elementor
├── assets/
│   ├── css/
│   │   └── elementor-custom.css  # CSS customizado para Elementor
│   ├── js/
│   │   └── main.js            # JavaScript principal
│   └── images/                # Imagens do tema
│       └── cta-pattern.svg    # Pattern decorativo
└── elementor-templates/
    └── homepage.json          # Template Elementor importavel
```

### Secoes da Homepage

1. **Hero** - Banner principal com CTA para WhatsApp
2. **Areas de Atuacao** - 6 cards com icones (Civil, Trabalhista, Criminal, Previdenciario, Empresarial, Familia)
3. **Sobre o Escritorio** - Texto + imagem + contadores animados
4. **Diferenciais** - 4 cards sobre fundo escuro
5. **Equipe** - Cards dos advogados com foto e OAB
6. **Depoimentos** - Testimonials de clientes
7. **CTA** - Chamada para acao com telefone e WhatsApp
8. **Footer** - 4 colunas (sobre, links, areas, contato)
9. **WhatsApp Float** - Botao flutuante fixo

### Classes CSS para Elementor

Use estas classes CSS nos widgets do Elementor para aplicar os estilos do tema:

| Classe | Uso |
|--------|-----|
| `rp-el-hero` | Secao hero |
| `rp-el-area-card` | Cards de areas de atuacao |
| `rp-el-team-card` | Cards da equipe |
| `rp-el-testimonial` | Cards de depoimentos |
| `rp-el-btn-primary` | Botao dourado |
| `rp-el-btn-whatsapp` | Botao WhatsApp verde |
| `rp-el-btn-outline` | Botao outline |
| `rp-el-section-dark` | Secao com fundo escuro |
| `rp-el-section-offwhite` | Secao com fundo off-white |
| `rp-el-counter` | Widget de contador |
| `rp-el-cta` | Secao CTA |
| `rp-el-diff-card` | Cards de diferenciais |
| `rp-heading-decorated` | Heading com linha decorativa |

### Cores do Tema

| Cor | Hex | Uso |
|-----|-----|-----|
| Azul Escuro (Primary) | `#1B2A4A` | Backgrounds, headings |
| Dourado (Secondary) | `#C9A84C` | Acentos, CTAs, destaques |
| Texto | `#2D2D2D` | Corpo do texto |
| Texto Light | `#6B6B6B` | Texto secundario |
| Off-white | `#F8F6F0` | Background alternativo |

---

### Suporte

Para duvidas sobre configuracao do tema, entre em contato com a equipe de desenvolvimento.
