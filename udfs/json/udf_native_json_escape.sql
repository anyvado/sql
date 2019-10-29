SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[udf_native_json_escape] (
	@source NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
	RETURN	CASE
    			WHEN @source IS NULL
                THEN 'null'
                ELSE '"'+STRING_ESCAPE(@source,'json')+'"'
    		END
END
GO

