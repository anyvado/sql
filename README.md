# Anyvado SQL

Anyvado SQL is a part of [Anyvado](https://anyvado.com) database structure. 
To learn more about Anyvado and its SQL features go to [Anyvado WIKI](http://wiki.anyvado.com/doku.php?id=core:ds:dbs:mssql:start)

## JSON SQL functions
We have created below functions for SQL to support the use of  [JSON paths](https://goessner.net/articles/JsonPath/).

 - **udf_native_json_escape** | Escapes strings for JSON
 - **udf_native_json_unescape** | Unescpare strings for JSON
 - **udf_native_json_to table** | Converts a JSON to TABLE
 - **udf_native_json_merge** | Merges two JSONs
 - **udf_native_json_update** | Updates a JSON by [JSON path](https://goessner.net/articles/JsonPath/)
 - **udf_native_json_validate** | Validates a JSON by conditions
 - **udf_native_json_value** | Returns a JSON value by [JSON path](https://goessner.net/articles/JsonPath/)
	 - **udf_native_json_value_path** (required UDF for udf_native_json_value)

# License

MIT License

Copyright (c) 2019 ANYVADO |  [Developers](mailto:developers@anyvado.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

