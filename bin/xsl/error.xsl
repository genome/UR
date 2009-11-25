<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="html"/>
  <xsl:output doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"/>
  <xsl:output doctype-public="-//W3C//DTD XHTML 1.0 Transitional//EN"/>

  <xsl:template match="/">

    <html>
      <head>
        <title>Analysis Web Dispatcher v0.1</title>
        <link rel="shortcut icon" href="/resources/report_resources/apipe_dashboard/images/gc_favicon.png" type="image/png" />
        <link rel="stylesheet" href="/resources/report_resources/apipe_dashboard/css/master.css" type="text/css" media="screen" />
        <style type="text/css" media="screen">
          div.container,
          div.background {
               width: 770px;
          }

          pre {
               white-space: pre-wrap; /* css-3 */
               white-space: -moz-pre-wrap !important; /* Mozilla, since 1999 */
               white-space: -pre-wrap; /* Opera 4-6 */
               white-space: -o-pre-wrap; /* Opera 7 */
               word-wrap: break-word; /* Internet Explorer 5.5+ */
          }
        </style>

      </head>

      <body>
        <div class="container">
          <div class="background" style="border-color: #7d000f">
            <h1 class="page_title" style="background-color: #a30013; border-color: #7d000f;">Analysis Web Dispatcher v0.1</h1>
            <div class="page_padding">
              <h2 style="color: #a30013">Error Encountered:</h2>
              <p><pre><xsl:value-of select="//error-msg/@error"/></pre></p>
            </div>

          </div>
        </div>
      </body>
    </html>

  </xsl:template>

</xsl:stylesheet>
