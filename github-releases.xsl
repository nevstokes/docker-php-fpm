<?xml version="1.0" encoding="utf-8"?>

<!-- https://gist.github.com/nevstokes/892ade6d04c4037a438391f279ed2780 -->
<xsl:stylesheet version="1.0"
                xmlns:atom="http://www.w3.org/2005/Atom"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
>

    <xsl:output method="text"/>

    <xsl:template match="/atom:feed">
        <xsl:apply-templates select="atom:entry"/>
    </xsl:template>

    <xsl:template match="atom:entry">
        <xsl:value-of select="atom:link/@href"/>
        <xsl:text>
</xsl:text>
    </xsl:template>

</xsl:stylesheet>