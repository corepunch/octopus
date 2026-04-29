<?xml version="1.0" encoding="UTF-8"?>
<!--
  src/page.xsl – XSLT template for all Octopus pages.

  Each page is defined as a small XHTML file (src/<name>.xhtml) that supplies
  only the unique body content and a few attributes:

    <page title="…"   – <title> text
          name="…"    – page script basename (js/pages/<name>.js)
          markdown="true|false">  – whether to include marked + DOMPurify
      <body>…page-specific HTML…</body>
    </page>

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
          <a class="nav-logo" href="index.html">🐙 Octopus</a>
          <div class="nav-links" id="nav-links"></div>
        </nav>

        <xsl:copy-of select="body/node()"/>

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
        <script src="js/pages/{@name}.js"></script>

      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
