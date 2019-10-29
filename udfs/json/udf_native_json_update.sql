SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_update] ( 
    @target NVARCHAR(MAX),	-- JSON Target 	
	@path NVARCHAR(MAX),    -- JSON Path	(path to token)
    @source NVARCHAR(MAX),	-- JSON Source 	(value to set)
    @options NVARCHAR(MAX)	-- JSON Options
    
)
RETURNS NVARCHAR(MAX)
AS
BEGIN

	/*
    	This UDF will update a JSON value in JSON by using JSON Path.
        http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:udf_json_update
    */

	IF ISNULL(@target,'') = '' 
    	RETURN @target	

	/* 0 = Set NULL value, 1 = Remove if NULL value, 2 = (only merge) Ignore */
    
	DECLARE	@updateNullOpt INT = ISNULL(dbo.udf_native_json_value(@options,'$.update_null', NULL, NULL),0),
    		@extend NVARCHAR(5) = dbo.udf_native_json_value(@options,'$.extend', NULL, NULL)

	/* Type specific variables - all others treated as strings */
  	DECLARE	@ValueBool BIT,
  			@ValueInt BIGINT,
            @ValueFloat FLOAT
            
	/* Dont try to cast into numerics if size of string if longer that 200 */
	IF LEN(@source)<50
	SELECT	@ValueBool = TRY_CAST(@source AS BIT),
  			@ValueInt = TRY_CAST(@source AS BIGINT),
            @ValueFloat = TRY_CAST(@source AS FLOAT)

	/* 	
    	Hack to avoid deleting keys with NULL values. (default in MS SQL 2017) 
    	We rename the NULL to -|null|- string and replace to null once JSON updated.
        This is optional behavior, default is true (update_null=0) 
        To force deletion (MS SQL behavior) define "update_null=1 ...
    */            
    RETURN	REPLACE
    		(
                CASE
                    WHEN 	@ValueInt IS NOT NULL
                    THEN	JSON_MODIFY(@target, @path, @ValueInt)
                    WHEN 	@valueBool IS NOT NULL
                    THEN	JSON_MODIFY(@target, @path, @ValueBool) 
                    WHEN 	@ValueFloat IS NOT NULL
                    THEN	JSON_MODIFY(@target, @path, @ValueFloat)                    
                    ELSE	CASE
            					WHEN 	@source IS NULL
                                THEN	CASE
                                            WHEN @updateNullOpt = 1
                                            THEN JSON_MODIFY(@target, @path, NULL)
                                            ELSE JSON_MODIFY(@target, @path,'-|null|-') 
                                        END 
                                        
                                WHEN	PATINDEX('%[[]%',@source) = 1
                                        OR
                                        PATINDEX('%{%',@source) = 1
                                THEN	CASE
                                			WHEN 	@extend = 'true'
                                            THEN 	JSON_MODIFY
                                            		(	@target,
                                                    	@path,
                                                        JSON_QUERY
                                                        (
                                                            dbo.udf_native_json_merge
                                                            (	dbo.udf_native_json_value(@target,@path,NULL,NULL),
                                                                JSON_QUERY(@source),
                                                                NULL
                                                            )
                                                        )
                                                    )
                                            ELSE 	JSON_MODIFY(@target, @path, JSON_QUERY(@source)) 
                                		END
                                ELSE 	JSON_MODIFY(@target, @path, @source)
                            END
                END,
            	'"-|null|-"',
                'null'
            )

END
GO

