SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_value]
( 
	@json nvarchar(max),
  	@path nvarchar(max),
  	@default nvarchar(max),
    @options nvarchar(max) -- reserved for "escape" options
)
RETURNS NVARCHAR(MAX)
AS
BEGIN

	/*
    	This function allows getting JSON values by using JSON paths.
        http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:udf_json_value
        
        Depends on:
        	dbo.udf_native_json_value_path
    */

	IF ISNULL(@json,'') = '' 
    	RETURN @default	
    
    DECLARE	@out NVARCHAR(MAX),
    		/* Option to unescape (default true) */
		    @Unescape BIT = ISNULL(JSON_VALUE(@options,'$.unescape'),1),
            /* Option to make NULL values to default */
            @NullDefault BIT = ISNULL(JSON_VALUE(@options,'$.null_default'),1),
            /* Option to force to array if [*] is object or string */
            @ForceArray BIT = ISNULL(JSON_VALUE(@options,'$.force_array'),0)

	/* Detect JSON PATH */
	IF 	PATINDEX('%[[][^0-9]%',@Path) > 0 OR @Unescape = 0
        SELECT	@out = j.Value
        FROM	dbo.udf_native_json_value_path(@json, @path, @options) j
    ELSE
    	BEGIN
        	-- Do not use ISNULL as it will limit JSON_QUERY to 8000 chars!
	    	SELECT	@out = COALESCE(JSON_VALUE(@json,@path),JSON_QUERY(@json, @path))
        END
    
        
	/* Set @out value or @default */
    SELECT	@out =
    	 	CASE
    			WHEN 	@out IS NULL AND @NullDefault = 1
                THEN	@default
                ELSE	@out
    		END
    IF @ForceArray = 1
        SELECT	@out = 
                CASE
                    WHEN CHARINDEX('[',LTRIM(@out))=1
                    THEN @out
                    ELSE '['+
                        CASE
                            WHEN  	CHARINDEX('"',LTRIM(@out))=1
                            OR		CHARINDEX('{',LTRIM(@out))=1
                            THEN 	@out
                            ELSE	dbo.udf_native_json_escape(@out)
                        END +
                    ']'
                END   
    RETURN @out
END
GO

