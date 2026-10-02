<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:wix="http://schemas.microsoft.com/wix/2006/wi">
  <xsl:output method="xml" encoding="UTF-8" indent="yes" />
  <xsl:key name="buildManifestComponent"
    match="wix:Component[wix:File[contains(@Source, 'native_assets.json')]]"
    use="@Id" />

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()" />
    </xsl:copy>
  </xsl:template>

  <!-- The root build manifest contains an absolute build-machine path. The
       runtime uses data/flutter_assets/NativeAssetsManifest.json instead. -->
  <xsl:template match="wix:Component[wix:File[contains(@Source, 'native_assets.json')]]" />
  <xsl:template match="wix:ComponentRef">
    <xsl:if test="not(key('buildManifestComponent', @Id))">
      <xsl:copy>
        <xsl:apply-templates select="@*|node()" />
      </xsl:copy>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
