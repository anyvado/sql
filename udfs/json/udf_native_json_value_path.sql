SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[udf_native_json_value_path] (
	@Json NVARCHAR(MAX), 
    @Token VARCHAR(8000),
    @Options NVARCHAR(MAX)
)
RETURNS @out TABLE(value NVARCHAR(MAX), type SMALLINT)
AS
BEGIN
/*
	This UDF is enables JSON PATH (http://goessner.net/articles/JsonPath/) queries.
    It is base for dbo.udf_native_json_value function.
    
    NOTE: 
    	It does not support UNION operators [,]
    
*/

	IF @Json IS NULL OR @Token IS NULL RETURN
    
	DECLARE	@Unescape BIT = ISNULL(JSON_VALUE(@options,'$.unescape'),1),
    		@Raw BIT = ISNULL(JSON_VALUE(@options,'$.raw'),0),
			@RestToken VARCHAR(8000),
			@UsedRestTokenRecursive BIT,
			@Value NVARCHAR(MAX),
			@Type SMALLINT

	IF @Token = '$' 
		BEGIN
			INSERT
			INTO	@out
			SELECT	@json, 
					CASE
						WHEN	CHARINDEX('[',@json) = 1
						THEN	4
						WHEN	CHARINDEX('{',@json) = 1
						THEN	5
						ELSE	NULL
					END 
		END
	ELSE
	IF ISNULL(PATINDEX('%[*?]%',@Token),0) > 0
		BEGIN
			;WITH Positions (Idx, Pos, PosType, PosDepth, OriginalToken, WithinSingleQuotes) AS
			(	SELECT	1, 0, 0, 0, @Token AS OriginalToken, 'false' as WithinSingleQuotes
				UNION	ALL
				SELECT	p.Idx+1,
						p.Pos + IIF(b.bStart < b.bEnd, b.bStart, b.bEnd) as Pos,
						IIF(b.bStart < b.bEnd, 1, 2) as PosType,
						IIF(b.bStart < b.bEnd, p.PosDepth + 1, p.PosDepth -1) as PosDepth,
						b.OriginalToken,
						c.WithinSingleQuotes
				FROM	Positions p
				OUTER
				APPLY	(	SELECT	-- Only [?..] and [*] - avoid numeric [0]
                					NULLIF(PATINDEX('%[[][^0-9]%',s.OriginalToken),0) AS bStart,
									NULLIF(PATINDEX('%[^0-9]]%',s.OriginalToken),0)+1 AS bEnd,
									s.OriginalToken
							FROM	(	SELECT	SUBSTRING(@Token,p.Pos,8000) AS OriginalToken
									)	AS s 
						)	b
				OUTER
				APPLY	(	-- Return if found position is within single quotes
							SELECT	IIF
									(	(	LEN(c.CurrentToken) - 
											LEN(REPLACE(c.CurrentToken,'''',''))
										) % 2 = 1,
										'true','false'
									)	AS WithinSingleQuotes
							FROM	(	SELECT	SUBSTRING(@Token, p.Pos + IIF(b.bStart < b.bEnd, b.bStart, b.bEnd),8000) AS CurrentToken
									)	c
						)	AS c
				WHERE	p.Pos IS NOT NULL
		
			), Tokens AS
			(
				SELECT	IIF(T.Token = '$.', '$', T.Token) AS Token,
						T.ArrayKeyClean, 
						Q.QueryKey,  Q.QueryOperator,
						-- Remove single quotes
						IIF 
						(	CHARINDEX('''',Q.QueryValue) = 1,
							SUBSTRING(Q.QueryValue,2,DATALENGTH(Q.QueryValue)-2),
							Q.QueryValue
						)	AS QueryValue,
						QT.*, 
						T.RestToken
				FROM	(
							SELECT	TOP (1)
									SUBSTRING(p.OriginalToken, 1, p.Pos-1) AS Token, 
									SUBSTRING(@Token, p.Pos, e.EndPos-p.Pos) AS ArrayKey,
									SUBSTRING(@Token, p.Pos+1, e.EndPos-(p.Pos+2)) AS ArrayKeyClean,
									'$'+NULLIF(SUBSTRING(p.OriginalToken,e.endPos,DATALENGTH(p.OriginalToken)),'') AS RestToken
							FROM	Positions p
							CROSS
							APPLY	(	SELECT	TOP (1) e.Pos as EndPos
										FROM	Positions e
										WHERE	e.WithinSingleQuotes = 'false'
										AND		e.Pos > p.Pos
										AND		e.PosDepth = p.PosDepth 
										AND		e.PosType = 2
										ORDER
										BY		e.Pos
										ASC
									)	AS e
							WHERE	p.PosType = 1
							AND		p.PosDepth = 1
							AND		p.WithinSingleQuotes = 'false'
							ORDER
							BY		p.Pos
							ASC
						)	AS T
				OUTER
				APPLY	(	SELECT	
									'$'+REVERSE(reversed.QueryKey) AS QueryKey,
									REVERSE(reversed.QueryOperator) AS QueryOperator,
									REVERSE(reversed.QueryValue) AS QueryValue
							FROM	(	SELECT	REVERSE(T.ArrayKeyClean) AS ReversedArrayKey,
												PATINDEX('[^)])[a-z0-9'']%',REVERSE(T.ArrayKey)) AS ValidQuery
									)	AS r
							OUTER	
							APPLY	(	SELECT	SUBSTRING
												(	
													r.ReversedArrayKey,
													qp.valuePos+1, qp.valueFirstPos-qp.valuePos
												)	AS QueryValue,
												SUBSTRING
												(	r.ReversedArrayKey,
													qp.operatorFirstPos,
													qp.tokenPos-(operatorFirstPos)
												)	AS QueryOperator,
												SUBSTRING
												(	r.ReversedArrayKey,
													qp.tokenPos,
													IIF(qp.bracketPos < qp.atPos, qp.bracketPos,qp.atPos)-(qp.tokenPos)
												)	AS QueryKey
										FROM	(	SELECT	PATINDEX('%[)]%',r.ReversedArrayKey) AS valuePos,
															PATINDEX('%[a-z0-9''][!<=>]%',r.ReversedArrayKey) AS valueFirstPos,
															PATINDEX('%[!<=>]%',r.ReversedArrayKey) AS operatorFirstPos,
															PATINDEX('%[!<=>][^!<=>]%',r.ReversedArrayKey)+1 AS tokenPos,
															NULLIF(PATINDEX('%]%',r.ReversedArrayKey),0) AS bracketPos, 
															PATINDEX('%[@]%',r.ReversedArrayKey) AS atPos
												)	qp
										WHERE	r.ValidQuery <> 0
									)	AS reversed
						)	Q
				OUTER
				APPLY	(	SELECT	'$'+rp.QueryToken AS QueryToken
				
							FROM	(	SELECT	SUBSTRING
												(	T.ArrayKeyClean, 
													p.P1,
													L-IIF
													(	p.revOp < revP1,
														(p.P1+p.revP1)-1,
														p.P1
													)
												)	AS QueryToken
										FROM	(
													SELECT	PATINDEX('%[@.]%',T.ArrayKeyClean)+1 AS P1,
															DATALENGTH(T.ArrayKeyClean) AS L,
															PATINDEX('%[.)]]%',REVERSE(T.ArrayKeyClean)) revP1,
															PATINDEX('%[!<=>]%',REVERSE(T.ArrayKeyClean)) revOp
												)	p
									)	AS rp
							WHERE	SUBSTRING(rp.QueryToken,DATALENGTH(rp.QueryToken),1) = ']'
						)	AS QT						
			), Results AS
			(
				SELECT	--*
						IIF
						(
							T.RestToken IS NOT NULL,
							J.rjValue, J.tjValue
						)	AS JsonValue,
						IIF
						(	T.RestToken IS NOT NULL,
							J.rjType, J.tjType	
						)	AS JsonType
				FROM	Tokens T
				CROSS	-- Root iteration of Token (tj)
				APPLY	(	
							SELECT	tj.[Value] as tjValue, tj.[Type] as tjType, 
									qj.Value as qjValue, qj.Type as qjType,
									rj.Value as rjValue, rj.Type as rjType
									,V.*
							FROM	OPENJSON(@Json, T.Token) tj
							OUTER	-- Query iteration of QueryToken (qj)
							APPLY	(	SELECT	qj.[Value], qj.[Type]
										FROM	dbo.udf_native_json_value_path
                                        		(tj.[Value], T.QueryToken, @options) qj
										WHERE	T.QueryToken IS NOT NULL
                                        AND		tj.[Type] IN (4,5)
									)	AS qj
							CROSS
							APPLY	(	SELECT	IIF
												(	T.QueryKey IS NOT NULL,
													ISNULL
													(	JSON_VALUE(ISNULL(qj.Value, tj.Value),T.QueryKey),
														JSON_QUERY(ISNULL(qj.Value, tj.Value),T.QueryKey)
													),
													ISNULL(qj.Value, tj.Value)
												)	AS QueryTokenValue
									)	V
							OUTER	-- Rest iteration of RestToken (rj)
							APPLY	(	SELECT	rj.[Value], rj.[Type]
										FROM	dbo.udf_native_json_value_path
                                        		( 	tj.Value, T.RestToken, 
                                                	dbo.udf_native_json_merge(@options,'{"raw":true}',null)) rj
										WHERE	T.RestToken IS NOT NULL
                                        AND		tj.[Type] IN (4,5)
									)	AS rj 
							/* Apply filter index on root */
							WHERE	(	T.ArrayKeyClean = '*'
										OR
										(
											TRY_CAST( T.ArrayKeyClean AS INT ) IS NULL
											OR
											tj.[key] = T.ArrayKeyClean
										)
									)
                            /* Apply type filter if rest token */
							AND		(	T.RestToken IS NULL
										OR
										tj.[Type] IN (4,5)
									)
							/* Apply query filter on root OR subqueried (recursive) json */
							AND		(	T.QueryOperator IS NULL
										OR
										(	( ( T.QueryOperator = '!='  OR  T.QueryOperator = '<>' ) AND V.QueryTokenValue <> T.QueryValue ) OR
											( T.QueryOperator = '==' AND V.QueryTokenValue = T.QueryValue ) OR
											( T.QueryOperator = '>=' AND V.QueryTokenValue >= T.QueryValue ) OR
											( T.QueryOperator = '<=' AND V.QueryTokenValue <= T.QueryValue ) OR
											( T.QueryOperator = '>' AND V.QueryTokenValue > T.QueryValue ) OR
											( T.QueryOperator = '<' AND V.QueryTokenValue < T.QueryValue ) 
                                            /* -- IN not supported normally - disabled for now 
                                            OR
											( T.QueryOperator = '><' AND V.QueryTokenValue IN 
													(	SELECT	TextValue
														FROM	dbo.udf_anyvado_core_utils_string_iterate_to_tbl
																(T.QueryValue,',')
													)
											) */
										)
									)
							
						)	AS J
			)
            INSERT
            INTO	@out
			SELECT	CASE 
            			WHEN J.cnt > 1 AND @Raw = 0
						THEN '[' 
						ELSE '' 
            		END+
					STRING_AGG(J.value,',')+
					CASE 
                    	WHEN J.cnt > 1 AND @Raw = 0
						THEN ']' 
						ELSE '' 
					END as value,
					J.type
			FROM	(	
						SELECT	CASE 
									WHEN @Raw = 0 AND r.JsonType = 1 AND (@unescape = 0 OR COUNT(*) OVER()>1)
									THEN '"'+STRING_ESCAPE(r.JsonValue,'json')+'"'
									ELSE r.JsonValue
								END as value, 
								CASE 
                                	WHEN COUNT(*) OVER() > 1 
									THEN 4 
									ELSE r.JsonType 
								END as type, 
								COUNT(*) OVER() as cnt
						FROM	Results r
					)	J
			GROUP 
			BY		J.cnt, J.type 
		END	
	ELSE
		BEGIN
			/* Default JSON token */
			INSERT
			INTO	@out
			SELECT	CASE 
            			WHEN o.cnt > 1 AND @Raw = 0
						THEN '[' 
						ELSE '' 
					END+
					STRING_AGG(o.value,',')+
					CASE 
						WHEN o.cnt > 1 AND @Raw = 0
						THEN ']' 
						ELSE '' 
					END as value,
					o.type
			FROM	(	
						SELECT	CASE 
									WHEN @Raw = 0 AND J.JsonType = 1 AND @unescape = 0
									THEN '"'+STRING_ESCAPE(J.JsonValue,'json')+'"'
									ELSE J.JsonValue
								END as value, 
								CASE 
									WHEN COUNT(*) OVER() > 1 
									THEN 4 
									ELSE J.JsonType 
								END as type, 
								COUNT(*) OVER() as cnt
						FROM	(	SELECT	SUBSTRING(@Token,1,T.LastDotPos) AS ParentToken,
											SUBSTRING(@Token,T.LastDotPos+2,DATALENGTH(@Token)) AS KeyName
									FROM	(	SELECT	DATALENGTH(@Token) - CHARINDEX('.',REVERSE(@Token)) AS LastDotPos
											)	T
								)	T
						OUTER
						APPLY	(	SELECT	o.[value] AS JsonValue, 
											o.[type] AS JsonType
									FROM	OPENJSON
											(	@json,
												T.ParentToken
											) AS o
									WHERE	o.[Key] = T.KeyName
								)	J
					)	AS o
			GROUP 
			BY		o.cnt, o.type 
		END

	RETURN
     
END
GO

