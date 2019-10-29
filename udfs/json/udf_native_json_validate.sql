SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_validate] (
	@source NVARCHAR(MAX),
    @conditions NVARCHAR(MAX),
    @options NVARCHAR(MAX),
    @condition NVARCHAR(10)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
	/*
    	This is a validation function for JSON string.
        http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:udf_json_validate
        
    */		
		SELECT	@condition = ISNULL(@condition,'AND')
                
		DECLARE	@result BIT,
				@requireAll BIT = dbo.udf_native_json_value(@options,'$.requireAll','false',NULL),
				@ignoreCaseAll BIT = dbo.udf_native_json_value(@options,'$.ignoreCaseAll','false',NULL),
                @debugInfo NVARCHAR(MAX) = '{"result":1,"logs":[]}',
                @debug BIT = dbo.udf_native_json_value(@options,'$.debug','false',NULL)
				
		

		DECLARE	@ctype NVARCHAR(20),
				@cpath NVARCHAR(1000), 
				@cvalue NVARCHAR(MAX),
                @cIndex INT,
                @IsNot BIT = 0


		IF ISNULL(@source,'')='' AND ISNULL(@conditions,'')='' RETURN 0;
		
		
        /* We count each type of array item so we can break loop sooner */
        DECLARE	@objCnt INT, @arrCnt INT, @strCnt INT
		SELECT	@objCnt = SUM(CASE WHEN PropertyType = 'Object' THEN 1 ELSE 0 END),
				@arrCnt = SUM(CASE WHEN PropertyType = 'Array' THEN 1 ELSE 0 END),
				@strCnt = SUM(CASE WHEN PropertyType = 'String' THEN 1 ELSE 0 END)
		FROM	dbo.udf_native_json_to_table(@conditions,null)
        

		DECLARE TCUR CURSOR LOCAL FAST_FORWARD 
		FOR 

		--#region SELECT 
		SELECT	c.PropertyType, c.PropertyPath, c.PropertyValue, c.PropertyIndex
		FROM	dbo.udf_native_json_to_table( @conditions, NULL ) c
		--#endregion

		OPEN TCUR
		FETCH	NEXT FROM TCUR 
		INTO	@ctype, @cpath, @cvalue, @cIndex 
	
		WHILE @@FETCH_STATUS = 0
			BEGIN	
				DECLARE @newResult BIT          
                
				/* String = Boolean operator */
				IF	@ctype = 'String' 
					BEGIN
						IF @debug = 1 SELECT @debugInfo =
                        	dbo.udf_native_json_update
                            (	@debugInfo,
                            	'append $.logs', 
                                'upd:'+@cvalue,
                                null
                            )
                        
						SELECT	@condition = 
                        		CASE
                                	WHEN 	@cvalue = 'not'
                                    THEN 	@condition
                                    ELSE 	@cvalue
                                END,
                                @IsNot = IIF(@cvalue = 'not',1,0),
                        		@strCnt = @strCnt -1
					END
				ELSE
				/* Array = New condition array */
				IF @ctype = 'Array'
					BEGIN
                    	DECLARE	@debugResult NVARCHAR(MAX)
						IF @debug = 1 
                        	BEGIN
                            	SELECT	@debugResult = dbo.udf_native_json_validate(@source, @cvalue, @options, @condition)
                                SELECT	@debugInfo =
                                			dbo.udf_native_json_update(@debugInfo, 'append $.logs',  
                                          		JSON_QUERY(dbo.udf_native_json_value(@debugResult,'$.logs','[]',NULL)),
                                          		NULL
                                        	)
                                            
                                SELECT	@newResult = 
                                            dbo.udf_native_json_value
                                                    (	@debugResult,
                                                        '$.result','1',
                                                        null
                                                    ),
                                        @arrCnt = @arrCnt - 1                                            
                            END
                        ELSE
                            SELECT	@newResult = dbo.udf_native_json_validate(@source, @cvalue, @options, @condition),
                                    @arrCnt = @arrCnt - 1
                                
						
					END
				ELSE
				IF @ctype = 'Object' 
					BEGIN
						
                    	SELECT	@objCnt = @objCnt - 1
                        
						--#region Init variables

						DECLARE	@cond_operator NVARCHAR(20) = dbo.udf_native_json_value(@cvalue,'$.operator',NULL,NULL),
								@cond_required NVARCHAR(10) = dbo.udf_native_json_value(@cvalue,'$.required',NULL,NULL),
								@cond_ignoreCase NVARCHAR(10) = dbo.udf_native_json_value(@cvalue,'$.ignoreCase',NULL,NULL),
								@cond_match NVARCHAR(10) = dbo.udf_native_json_value(@cvalue,'$.match',NULL,NULL),
								@cond_aggregate NVARCHAR(20) = dbo.udf_native_json_value(@cvalue,'$.aggregate',NULL,NULL),
								@cond_path NVARCHAR(1000) = dbo.udf_native_json_value(@cvalue,'$.path',NULL,NULL),
								@cond_value NVARCHAR(1000) = dbo.udf_native_json_value(@cvalue,'$.value',NULL,NULL),
                                @cond_valuePath NVARCHAR(1000) = dbo.udf_native_json_value(@cvalue,'$.valuePath',NULL,NULL)
						
                        IF @cond_valuePath IS NOT NULL
                        	SELECT @cond_value = dbo.udf_native_json_value(@cvalue,@cond_valuePath,NULL,NULL)
                            
						DECLARE	@src_agg_value FLOAT,
								@src_value NVARCHAR(MAX) = dbo.udf_native_json_value(@source,@cond_path,NULL,NULL)

						DECLARE	@cond_type NVARCHAR(20) = 
									CASE
										WHEN	CHARINDEX('[',@cond_value) = 1
										THEN	'Array'
										WHEN	CHARINDEX('{',@cond_value) = 1
										THEN	'Object'
										ELSE	'Other'
									END,
								@src_type NVARCHAR(20) =	
									CASE
										WHEN	CHARINDEX('[',@src_value) = 1
										THEN	'Array'
										WHEN	CHARINDEX('{',@src_value) = 1
										THEN	'Object'
										ELSE	'Other'
									END				
								

						-- Aggregate source value if option available	
						IF @src_type = 'Array' AND ISNULL(@cond_aggregate,'') <> ''
							SELECT	@src_agg_value =
										CASE
											WHEN	@cond_aggregate IN ('max')
											THEN	( SELECT MAX(PropertyValue) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('min')
											THEN	( SELECT MIN(PropertyValue) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('avg')
											THEN	( SELECT AVG(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('sum')
											THEN	( SELECT SUM(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('var')
											THEN	( SELECT VAR(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('varp')
											THEN	( SELECT VARP(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('stdev')
											THEN	( SELECT STDEV(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('stdevp')
											THEN	( SELECT STDEVP(TRY_CAST(PropertyValue AS FLOAT)) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											WHEN	@cond_aggregate IN ('count','cnt')
											THEN	( SELECT COUNT_BIG(PropertyValue) FROM dbo.udf_native_json_to_table(@src_value,NULL) )
											ELSE	NULL
										END
						--#endregion
                        
						--#region Condition evaluation
                        
						SELECT @newResult =
									CASE
                                        WHEN	(@requireAll = 1 OR @cond_required = 'true') 
                                        		AND
                                                ISNULL(@src_value,'') = ''
                                        THEN	0
                                        WHEN	@cond_operator IN('exists')
                                        THEN	IIF(ISNULL(@src_value,'') <>'',1,0)
                                        WHEN	@cond_operator IN('null','isNull')
                                        THEN	IIF(@src_value IS NULL,1,0)
                                        WHEN	@cond_operator IN ('nullOrEmpty','isNullOrEmpty')
                                        THEN	IIF(@src_value = '',1,0)

										--#region General conditions 

										WHEN	@cond_type = 'Other'
										THEN	CASE
													WHEN	@cond_operator IN ('=')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value = @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS = @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS = @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('<>','!=')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value <> @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS <> @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS <> @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END					
													WHEN	@cond_operator IN ('>')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value > @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS > @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS > @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('>=')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value >= @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS >= @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS >= @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('<')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value < @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS < @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS < @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('<=')
													THEN	CASE
																WHEN	@src_agg_value IS NOT NULL
																THEN	IIF(@src_agg_value <= @cond_value,1,0)
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS <= @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS <= @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('starts','begin','beginsWith','startsWith')
													THEN	CASE
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS LIKE CONCAT(@cond_value,'%') COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS LIKE CONCAT(@cond_value,'%') COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('ends','stops','endsWith','stopsWith')
													THEN	CASE
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS LIKE CONCAT('%',@cond_value) COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS LIKE CONCAT('%',@cond_value) COLLATE Latin1_General_100_CS_AS,1,0)
															END
													WHEN	@cond_operator IN ('has','contains','in')
													THEN	CASE
																WHEN	@src_type = 'Array'
																THEN	CASE
																			WHEN	@cond_ignoreCase = 'true'
																			THEN	(
																						SELECT	IIF(COUNT(m.PropertyValue) >= 1,1,0)
																						FROM	dbo.udf_native_json_to_table(@src_value,NULL) m
																						WHERE	m.PropertyValue COLLATE Latin1_General_100_CI_AS
																								= 
																								@cond_value COLLATE Latin1_General_100_CI_AS
																					)
																			ELSE	(
																						SELECT	IIF(COUNT(m.PropertyValue) >= 1,1,0)
																						FROM	dbo.udf_native_json_to_table(@src_value,NULL) m
																						WHERE	m.PropertyValue COLLATE Latin1_General_100_CS_AS
																								= 
																								@cond_value COLLATE Latin1_General_100_CS_AS
																					)
																
																		END	
																ELSE	CASE
																			WHEN	@cond_ignoreCase = 'true'
																			THEN	IIF(@src_value COLLATE Latin1_General_100_CI_AS LIKE CONCAT('%',@cond_value,'%') COLLATE Latin1_General_100_CI_AS,1,0)
																			ELSE	IIF(@src_value COLLATE Latin1_General_100_CS_AS LIKE CONCAT('%',@cond_value,'%') COLLATE Latin1_General_100_CS_AS,1,0)
																		END
															END
													WHEN	@cond_operator IN ('like','isSubString')
													THEN	CASE
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF(CONCAT('%',@src_value,'%') COLLATE Latin1_General_100_CI_AS LIKE @cond_value COLLATE Latin1_General_100_CI_AS,1,0)
																ELSE	IIF(CONCAT('%',@src_value,'%') COLLATE Latin1_General_100_CS_AS LIKE @cond_value COLLATE Latin1_General_100_CS_AS,1,0)
															END

												END
										--#endregion

										--#region Array (condition value)
					
										WHEN	@cond_type = 'Array'
										THEN	CASE
													WHEN	@cond_operator IN ('between')
													THEN	CASE
																WHEN	@cond_ignoreCase = 'true'
																THEN	IIF
																		(	(	@src_value COLLATE Latin1_General_100_CI_AS >= dbo.udf_native_json_value(@cond_value,'$[0]',NULL,NULL) COLLATE Latin1_General_100_CI_AS
																				AND
																				@src_value COLLATE Latin1_General_100_CI_AS <= dbo.udf_native_json_value(@cond_value,'$[1]',NULL,NULL) COLLATE Latin1_General_100_CI_AS
																			), 1,0
																		)
																ELSE	IIF
																		(	(	@src_value COLLATE Latin1_General_100_CS_AS >= dbo.udf_native_json_value(@cond_value,'$[0]',NULL,NULL) COLLATE Latin1_General_100_CS_AS
																				AND
																				@src_value COLLATE Latin1_General_100_CS_AS <= dbo.udf_native_json_value(@cond_value,'$[1]',NULL,NULL) COLLATE Latin1_General_100_CS_AS
																			), 1,0
																		)							
															END
													WHEN	@cond_operator IN ('in')
													THEN	CASE
																WHEN	@src_type = 'Array'
																THEN	CASE
																			WHEN	@cond_ignoreCase = 'true'
																			THEN	(	SELECT	CASE
																									WHEN	@cond_match IN ('all')
																									THEN	IIF
																											(	COUNT(s.PropertyIndex) 
																												>= 
																												(
																													SELECT	COUNT(*) AS cnt
																													FROM	dbo.udf_native_json_to_table(@cond_value,NULL)
																													--WHERE	PropertyLevel > 0
																												),
																												1,0
																											)
																									ELSE	IIF
																											(	
																												COUNT(s.PropertyIndex) > 0,
																												1, 0
																											)
																						
																								END
																			
																						FROM	dbo.udf_native_json_to_table(@src_value,NULL) s
																						JOIN	(
																									SELECT	DISTINCT
																											PropertyValue AS value
																									FROM	dbo.udf_native_json_to_table(@cond_value,NULL)
																								)	AS t
																						ON		t.value COLLATE Latin1_General_100_CI_AS = s.PropertyValue COLLATE Latin1_General_100_CI_AS
																					)
																			ELSE	(	SELECT	IIF
																								(	COUNT(s.PropertyIndex) 
																									>= 
																									(
																										SELECT	COUNT(*) AS cnt
																										FROM	dbo.udf_native_json_to_table(@cond_value,NULL)
																										--WHERE	PropertyLevel > 0
																									),
																									1,0
																								)
																						FROM	dbo.udf_native_json_to_table(@src_value,NULL) s
																						JOIN	(
																									SELECT	DISTINCT
																											PropertyValue AS value
																									FROM	dbo.udf_native_json_to_table(@cond_value,NULL)
																								)	AS t
																						ON		t.value COLLATE Latin1_General_100_CS_AS = s.PropertyValue COLLATE Latin1_General_100_CS_AS
																	
																	
																					)
																		END
																ELSE	CASE
																			WHEN	@cond_ignoreCase = 'true'
																			THEN	(
																						SELECT	IIF(COUNT(m.PropertyValue) >= 1,1,0)
																						FROM	dbo.udf_native_json_to_table(@cond_value,NULL) m
																						WHERE	m.PropertyValue COLLATE Latin1_General_100_CI_AS
																								= 
																								@src_value COLLATE Latin1_General_100_CI_AS
																					)
																			ELSE	(
																						SELECT	IIF(COUNT(m.PropertyValue) >= 1,1,0)
																						FROM	dbo.udf_native_json_to_table(@cond_value,NULL) m
																						WHERE	m.PropertyValue COLLATE Latin1_General_100_CS_AS
																								= 
																								@src_value COLLATE Latin1_General_100_CS_AS
																					)
																
																		END
															END
												END
										--#endregion
					
										ELSE	0
									END 
                                       
						--#endregion    
						      
						

					END
                    
					IF (@ctype IN ('Array','Object'))
                    BEGIN
                        SELECT	@result =
                                  CASE	
                                        WHEN	@condition = 'and'
                                        THEN	CASE
                                        			WHEN	@result IS NULL
                                                    THEN  	@newresult
                                                    ELSE	IIF(@result = @newresult,1,0)
                                        		END
                                        WHEN	@condition = 'or'
                                        THEN	IIF(@result = 1 OR @newresult = 1,1,0)
                                        WHEN	@condition = 'xor'
                                        THEN	CASE
                                                    WHEN	@result IS NULL 
                                                    THEN	@newResult
                                                    ELSE	@result ^ @newresult
                                                END
                                    END   
                        
                        IF @IsNot = 1 
	                        SELECT 	@Result = IIF(@Result=0,1,0)
                        
						IF @debug = 1
                        SELECT @debugInfo =
                            dbo.udf_native_json_update
                            (	@debugInfo,
	                            'append $.logs', 
                                CASE
                                	WHEN	@ctype = 'Array'
                                    THEN	@condition+'.out:'+ISNULL(CAST(@Result AS VARCHAR),'null')
                                    ELSE	@condition+':'+
                                    		@cond_path+'('+ISNULL(@cond_value,'null')+')'+
                                            @cond_operator+
                                            ISNULL
                                            (
                                            	@cond_valuePath+'('+ISNULL(@src_value,'null')+')',
                                            	ISNULL(@src_value,'null')
                                            )+
                                            ':'+CAST(@Result AS NVARCHAR(1))
                                END,
                                NULL
                            )                             
                                               
	                    SELECT @IsNot = 0
                            
						-- Stop if evaluation of further conditions is not required.
                        IF  (@requireAll = 0) AND
                            (@strCnt = 0)
                            BEGIN
                                IF (@result = 0 AND @condition = 'and') 
                                OR (@result = 1 AND @condition = 'or')
                                    BREAK;
                            END

                    END
                    
				FETCH	NEXT FROM TCUR 
				INTO	@ctype, @cpath, @cvalue, @cIndex 
			END
		CLOSE TCUR
		DEALLOCATE TCUR
        
        IF @debug = 1
          SELECT @debugInfo = dbo.udf_native_json_update(@debugInfo,'$.result',IIF(@result=1,'true','false'),NULL)
          
        RETURN	CASE
        			WHEN @debug = 1
                    THEN @debugInfo
                    ELSE CAST(@result as NVARCHAR(1))
        		END
            
END
GO

