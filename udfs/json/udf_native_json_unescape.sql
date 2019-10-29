SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[udf_native_json_unescape] (
	@source NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
	SELECT @source = LTRIM(RTRIM(@source))
	IF CHARINDEX('"',@source) <> 1 RETURN @source

  	RETURN JSON_VALUE('{"text":'+@source,'$.text')
END
GO

