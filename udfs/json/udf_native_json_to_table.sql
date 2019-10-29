SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_to_table] (
	@json NVARCHAR(MAX), 	-- JSON to convert to TABLE
    @options NVARCHAR(MAX)	-- JSON options
)	

RETURNS	@JsonTable 
TABLE	(	PropertyPath NVARCHAR(MAX),
			PropertyPathSafe NVARCHAR(MAX),
            PropertyName NVARCHAR(MAX),
            PropertyValue NVARCHAR(MAX),
            PropertyType NVARCHAR(50),
            PropertyIndex INT,
            PropertyPosition INT,
            PropertyLevel INT
        )
AS
BEGIN
	/*
    	This UDF will input a JSON and output its content as TABLE.
        http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:udf_json_to_table
        
        Options:
        	{
            	"root": "r" -- customization of rootname, default is $
                "recursice": bool -- if true, recursively iterate all objects/arrays.
            }
    */
    
	DECLARE	@root NVARCHAR(MAX) = dbo.udf_native_json_value(@options,'$.root','$',NULL),
    		@rootType NVARCHAR(10) =
				CASE
					WHEN CHARINDEX('[',@json) = 1
					THEN 'Array'
					WHEN CHARINDEX('{',@json) = 1
					THEN 'Object'
				END,
			@recursive BIT = IIF(dbo.udf_native_json_value(@options,'$.recursive','false',NULL) = 'true', 1, 0)
               
    ;WITH CTE AS 
        (	
            SELECT	CAST
            		(	@root 
                    	COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyPath, 
                    CAST
            		(	@root 
                    	COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyPathSafe, 
                    CAST
                    ('' 
                    	COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyName, 
                    CAST
                    (	@json 
                    	COLLATE DATABASE_DEFAULT AS NVARCHAR(MAX)
                    ) AS PropertyValue,
                     
                    CAST
                    (	CASE
                            WHEN CHARINDEX('[',@json) = 1
                            THEN 'Array'
                            WHEN CHARINDEX('{',@json) = 1
                            THEN 'Object'
                        END
                    	COLLATE DATABASE_DEFAULT AS NVARCHAR(20)
                    ) AS PropertyType, 
                    
                    -1 AS PropertyLevel,
                    CAST('0' COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)) AS PropertyIndex,
                    CAST('0' COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)) AS PropertyPosition
                    
            UNION	ALL
            SELECT	CAST
                    (
                        (
                            CTE.PropertyPath+
                            CASE
                                WHEN CTE.PropertyType = 'Array'
                                THEN '['+j.[Key]+']'
                                ELSE  '.'+j.[Key]
                            END 
                        ) COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyPath,
                    CAST
                    (
                        (
                            CTE.PropertyPathSafe+
                            CASE
                                WHEN CTE.PropertyType = 'Array'
                                THEN '['+j.[Key]+']'
                                ELSE  '.'+
                                	CASE
                                		WHEN PATINDEX('%[^0-9a-z]%',j.[key]) = 0
                                        THEN j.[Key]
                                        ELSE '"'+j.[Key]+'"'
                                    END 
                            END 
                        ) COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyPathSafe,
                    CAST
                    (	j.[key] COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyName, 
                    CAST
                    (	j.[value] COLLATE DATABASE_DEFAULT AS NVARCHAR(MAX)
                    ) AS PropertyValue, 
                    CAST
                    (	CASE j.[type]
                            WHEN 0 THEN 'Null'
                            WHEN 1 THEN 'String'
                            WHEN 2 THEN 
                            	CASE
                                	WHEN	CHARINDEX('.',j.[value])>0
                                    THEN	'Float'
                                	ELSE	'Integer'
                                END
                            WHEN 3 THEN 'Boolean'
                            WHEN 4 THEN 'Array'
                            WHEN 5 THEN 'Object'
                        END	
                        COLLATE DATABASE_DEFAULT AS NVARCHAR(20)
                    ) AS PropertyType, 
                    CTE.PropertyLevel + 1 AS PropertyLevel,
                    CAST
                    (	CASE
                    		WHEN 	CTE.PropertyType = 'Array'
                            THEN	CAST( ROW_NUMBER() OVER(ORDER BY CTE.PropertyPosition)-1 AS NVARCHAR(1000) )
                            ELSE	CAST( CTE.PropertyIndex AS NVARCHAR(1000) )
                    	END 
                        COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyIndex,
                    CAST
                    (	CAST( ROW_NUMBER() OVER(ORDER BY CTE.PropertyPosition)-1 AS NVARCHAR(1000) )
                        COLLATE DATABASE_DEFAULT AS NVARCHAR(1000)
                    ) AS PropertyPosition
                    
                    
                    

            FROM	CTE
            CROSS
            APPLY	OPENJSON(CTE.PropertyValue) j
            WHERE	CTE.PropertyType IN ('Array','Object')
            AND		(	@recursive = 1
                        OR
                        (	@recursive = 0
                            AND
                            CTE.PropertyLevel < 0
                        )
                    )
        )

		INSERT
        INTO	@JsonTable
        		( 	PropertyPath, PropertyPathSafe, 
                	PropertyName, PropertyValue, PropertyType,
                    PropertyIndex, PropertyPosition,
                    PropertyLevel
                )
        SELECT	PropertyPath, PropertyPathSafe, 
                PropertyName, PropertyValue, PropertyType,
                PropertyIndex, PropertyPosition,
                PropertyLevel
        FROM	CTE	
        WHERE	CTE.PropertyPath <> @root
        		        
        RETURN;
END
GO

