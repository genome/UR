<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  <xsl:output method="html"/>
  <xsl:output doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"/>
  <xsl:output doctype-public="-//W3C//DTD XHTML 1.0 Transitional//EN"/>

  <!-- include page resources -->
  <xsl:include href="includes/dashboard_header.xsl"/>
  
  <xsl:template match="/">
    
    <html>
      <head>
        <title>Analysis Dashboard v0.0.1</title>
        <link rel="shortcut icon" href="/resources/report_resources/apipe_dashboard/images/gc_favicon.png" type="image/png" />
        <link rel="stylesheet" href="/resources/report_resources/apipe_dashboard/css/master.css" type="text/css" media="screen" />
        <style type="text/css" media="screen">
          div.container,
          div.background {
               width: 670px;
          }
          div.search_form_container {
          float: left;
          width: 640px;
          background: #e7e7e7;
          padding: 15px;
          border-bottom: 1px solid #CCC;
          }
          div.search_form {
          width: 49%;
          float: left;
          }
          
          table.form {
          margin: 0;
          }
          div.search_help {
          width: 49%;
          float: right;
          }

        </style>

      </head>

      <body>
        <div class="container">
          <div class="background">
            <xsl:copy-of select="$dashboard_header"/>
            <div class="search_form_container">
              <div class="search_form">
                <form method="get" action="/cgi-bin/search/index.cgi">
                  <table cellspacing="0" cellpadding="0" border="0" class="form">
                    <tr>
                      <td style="white-space: nowrap; font-weight: bold;">
                        GC Search:
                      </td>
                      <td>
                        <input type="text" size="30" name="query" style="background-color: #FFF; font-size: 120%;"/><br/>
                      </td>
                      <td>
                        <input type="submit" class="search_button" value="Search"/>
                      </td>
                    </tr>
                  </table>
                </form>
              </div>
              <div class="search_help">
                <p></p>
              </div>
            </div>
            <div class="page_padding">
              <br/>
              <br/>
              <h2 class="form_group" style="padding-top: 15px;">Search for Models and Builds</h2>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="model_name" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Model Name:</td>
                      <td class="input">
                        <input type="text" name="genome-model-name" value="" />
                      </td>
                      <td>
                        <input type="submit" name="Search" value="Search for Model Name" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="model_id" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Model ID:</td>
                      <td class="input">
                        <input type="text" name="genome-model-id" value="" />
                      </td>
                      <td>
                        <input type="submit" name="Search" value="Search for Model ID" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="model_user" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Models Owned by User:</td>
                      <td class="input">
                        <select name="user_name">
                          <option value="" selected="selected">Select a User</option>
                          <xsl:for-each select="//users/user">
                            <option><xsl:attribute name="value"><xsl:value-of select="."/></xsl:attribute><xsl:value-of select="."/></option>
                          </xsl:for-each>
                        </select>
                      </td>
                      <td>
                        <input type="submit" name="Search" value="Search for Models" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="build_id" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Build ID:</td>
                      <td class="input">
                        <input type="text" name="build-id" value="" />
                      </td>
                      <td>
                        <input type="submit" name="Search" value="Search for Build ID" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="build_status" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Builds with Status:</td>
                      <td class="input">
                        <select name="event_status">
                          <option value="" selected="selected">Select a Status</option>
                          <xsl:for-each select="//event-statuses/event-status">
                            <option><xsl:attribute name="value"><xsl:value-of select="."/></xsl:attribute><xsl:value-of select="."/></option>
                          </xsl:for-each>
                        </select>
                      </td>
                      <td>
                        <input type="submit" name="Search" value="Search for Builds" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
              <h2 class="form_group">Compare Model GoldSNP Metrics</h2>
              <form action="status.cgi" method="GET">
                <input type="hidden" name="search_type" value="model_goldsnp_comparison" />
                <table cellpadding="0" cellspacing="0" border="0" class="form" width="100%">
                  <colgroup>
                    <col width="25%"/>
                    <col width="30%"/>
                    <col width="100%"/>               
                  </colgroup>
                  <tbody>
                    <tr>
                      <td class="label">Model ID 1:</td>
                      <td class="input">
                        <input type="text" name="model-id-compare-1" value="2817078814" />
                      </td>
                      <td>
                        
                      </td>
                    </tr>
                    <tr>
                      <td class="label">Model ID 2:</td>
                      <td class="input">
                        <input type="text" name="model-id-compare-2" value="2818011518" />
                      </td>
                      <td>
                        
                      </td>
                    </tr>
                    <tr>
                      <td class="label">Model ID 3:</td>
                      <td class="input">
                        <input type="text" name="model-id-compare-3" value="" />
                      </td>
                      <td>
                        
                      </td>
                    </tr>
                    <tr>
                      <td class="label">Model ID 4:</td>
                      <td class="input">
                        <input type="text" name="model-id-compare-4" value="" />
                      </td>
                      <td>
                        
                      </td>
                    </tr>
                    <tr>
                      <td class="label">Model ID 5:</td>
                      <td class="input">
                        <input type="text" name="model-id-compare-5" value="" />
                      </td>
                      <td>
                        
                      </td>
                    </tr>
                    <tr>
                      <td class="label"></td>
                      <td class="input">

                      </td>
                      <td>
                        <input type="submit" name="Search" value="Compare Models" />                        
                      </td>
                    </tr>
                  </tbody>
                </table>
              </form>
            </div>
          </div>
        </div>
      </body>
    </html>

  </xsl:template>

</xsl:stylesheet>
