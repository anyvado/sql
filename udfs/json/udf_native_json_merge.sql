SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_merge] (
	@target NVARCHAR(MAX), -- Target JSON 
    @source NVARCHAR(MAX), -- Source JSON
    @options NVARCHAR(MAX) -- Options JSON
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
  	/*
    	This UDF will merge the @target JSON with @source JSON.
        http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:udf_json_merge
    */
    
	IF ISNULL(@target,'') = '' AND ISNULL(@source,'')<>''
    	RETURN @source
    IF ISNULL(@source,'') = '' AND ISNULL(@target,'')<>''
    	RETURN @target
    IF ISNULL(@source,'') = '' AND ISNULL(@target,'')=''
    	RETURN NULL;
        
	/* 	Merge options 
            { 
              "update_array": integer,
              "update_null": integer
            }	
        	----------------
    		@updateArrOpt:
            	0 = Concatenate (merge everything even if identical)
                1 = Union (add only non-existing)
                2 = Replace all (clears target before merge)
                3 = Replaces targets by source index 
            @updateNullOpt:
	            0 = Apply NULL value 
                1 = Remove if NULL value 
                2 = Ignore (dont merge)
    */      
      
    DECLARE	@updateArrOpt INT = ISNULL(dbo.udf_native_json_value(@options,'$.update_array', NULL, NULL),1),
            @updateNullOpt INT = ISNULL(dbo.udf_native_json_value(@options,'$.update_null', NULL, NULL),0),
            /* Remember the root type (array or object) */
            @rootType NVARCHAR(20) =
				CASE
                    WHEN CHARINDEX('[',@source) = 1
                    THEN 'Array'
                    WHEN CHARINDEX('{',@source) = 1
                    THEN 'Object'
                END

    -- Clear array if merge_arr = 2 (replace all)
	IF @rootType = 'Array' AND @updateArrOpt = 2 SELECT @target = '[]'

	SELECT	@target =	CASE	
							WHEN	src.PropertyType IN('Object','Array')
							THEN	CASE
										WHEN	trg.PropertyType IS NULL 
												OR 
												trg.PropertyType <> src.PropertyType
										THEN	CASE
                                        			WHEN @rootType = 'Array'
                                                    THEN dbo.udf_native_json_update(@target, 'append $', src.PropertyValue, src.PropertyType, @options)
                                                    ELSE dbo.udf_native_json_update(@target, src.PropertyPathSafe, src.PropertyValue, src.PropertyType, @options)
                                        		END
										ELSE	dbo.udf_native_json_update
												(	@target, src.PropertyPathSafe, 
													dbo.udf_native_json_merge
													(	trg.PropertyValue, src.PropertyValue, @options ),
                                                    src.PropertyType,
													@options
												)
									END
							ELSE	CASE
										WHEN	@rootType = 'Array'
										THEN	CASE 
													-- Concatenate arrays OR Replace all array items 
													WHEN	@updateArrOpt IN (0,2) 
													THEN	dbo.udf_native_json_update(@target, 'append $', src.PropertyValue, src.PropertyType, @options)
													-- Union arrays, skipping items that already exist.
													WHEN	@updateArrOpt = 1 AND (trg.PropertyType IS NULL OR trg.PropertyValue <> src.PropertyValue)
													THEN	dbo.udf_native_json_update(@target, 'append $', src.PropertyValue, src.PropertyType, @options)
													-- Merge array items together, matched by index.
													WHEN	@updateArrOpt = 3 AND trg.PropertyType IS NULL
													THEN	dbo.udf_native_json_update(@target, 'append $', src.PropertyValue, src.PropertyType, @options)
													WHEN	@updateArrOpt = 3 AND trg.PropertyType IS NOT NULL
													THEN	dbo.udf_native_json_update(@target, src.PropertyPathSafe, src.PropertyValue, src.PropertyType, @options)
													ELSE	@target
												END
										ELSE	CASE
													WHEN	src.PropertyType = 'Null' AND @updateNullOpt = 2
													THEN	@target
													ELSE	dbo.udf_native_json_update(@target, src.PropertyPathSafe, src.PropertyValue, src.PropertyType, @options)
												END
									END		
						END	
    FROM	(
                SELECT	PropertyPathSafe,
                        PropertyName,
                        PropertyValue,
                        PropertyType,
                        PropertyIndex,
                        PropertyLevel
                FROM	dbo.udf_native_json_to_table(@source, NULL) AS src
            )	AS src
    OUTER 
    APPLY	(	SELECT	DISTINCT
                        trg.PropertyPathSafe,
                        trg.PropertyValue,
                        trg.PropertyType
                FROM	dbo.udf_native_json_to_table(@target, NULL) trg
                WHERE	(	@rootType = 'Object'
                            AND
                            trg.PropertyPathSafe = src.PropertyPathSafe
                        )
                OR		(	@rootType = 'Array'
                            AND
                            (	(
                                    -- Replace by index option
                                    @updateArrOpt = 3 
                                    AND 
                                    trg.PropertyIndex = src.PropertyIndex
                                )
                                
                                OR
                                (	-- Union option 
                                	@updateArrOpt = 1
                                    AND
                                    (	trg.PropertyValue = src.PropertyValue
                                    )
                                )
                            )
                        )
            )	AS trg

    RETURN 	@target   
    
END
GO

