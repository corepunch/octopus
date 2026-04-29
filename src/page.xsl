<?xml version="1.0" encoding="UTF-8"?>
<!--
  src/page.xsl – XSLT template for all Octopus pages.

  Pages are authored as small XHTML files in src/ and transformed into dist/
  HTML files by scripts/build.sh using xsltproc.  Edit the XHTML sources,
  not the generated HTML files.

  Each page is defined as a small XHTML file (src/<name>.xhtml) that supplies
  only the unique body content and a few attributes:

    <page title="…"   – <title> text
          name="…"    – page script basename (js/pages/<name>.js)
                         omit for type="static" pages with no page JS
          type="…"    – layout type: "feed" (default) or "static"
          markdown="true|false">  – whether to include marked + DOMPurify
      …page-specific HTML…
    </page>

  Layout types:
    type="feed"   (default) – two-column layout with sidebar; includes
                              js/pages/<name>.js and all runtime scripts.
    type="static"           – no sidebar; centered single-column content via
                              .static-col; auth/nav scripts still loaded so
                              the nav bar renders, but no page-specific JS.

  The build script (scripts/build.sh) transforms every src/*.xhtml file into
  a root-level *.html file using xsltproc.
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!-- libxslt outputs "<!DOCTYPE html>" (HTML5) when doctype-system="about:legacy-compat" -->
  <xsl:output method="html" encoding="UTF-8" indent="yes"
              doctype-system="about:legacy-compat"/>

  <xsl:template match="/page">
    <html lang="en">
      <head>
        <meta charset="UTF-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <title><xsl:value-of select="@title"/></title>
        <link rel="stylesheet" href="css/style.css"/>
      </head>
      <body>

        <nav id="nav">
          <div class="nav-inner">
            <div class="nav-1">
              <a class="nav-logo" href="index.html">🐙 Octopus</a>
            </div>
            <div class="nav-2" id="nav-center">
              <xsl:for-each select="nav-center/node()">
                <xsl:copy-of select="."/>
              </xsl:for-each>
            </div>
            <div class="nav-3">
              <div class="nav-links" id="nav-links"></div>
            </div>
          </div>
        </nav>

        <xsl:for-each select="node()[not(self::nav-center)]">
          <xsl:copy-of select="."/>
        </xsl:for-each>

        <!-- Required CDN scripts in fixed order -->
        <script src="https://cdn.jsdelivr.net/npm/handlebars@4.7.8/dist/handlebars.min.js"></script>
        <xsl:if test="@markdown='true'">
          <script src="https://cdn.jsdelivr.net/npm/marked@11/marked.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/dompurify@3.2.5/dist/purify.min.js"></script>
        </xsl:if>
        <script src="https://cdn.jsdelivr.net/npm/appwrite@16/dist/iife/sdk.js"></script>
        <script src="js/config.js"></script>
        <script src="js/appwrite.js"></script>
        <script src="js/templates.js"></script>
        <script src="js/utils.js"></script>
        <script src="js/icons.js"></script>
        <script src="js/auth.js"></script>
        <xsl:if test="not(@type='static')">
          <script src="js/pages/{@name}.js"></script>
        </xsl:if>

      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
