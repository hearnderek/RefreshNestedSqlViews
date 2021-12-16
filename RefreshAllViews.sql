PRINT N' -- Refreshing all VIEWS in database ' + QUOTENAME(DB_NAME()) + ' :'
DECLARE @stmt_refresh_object nvarchar(400)
DECLARE c_refresh_object CURSOR FOR
WITH DepTree AS (
  -- !! RECURSIVE CTE !!
  SELECT  o.name, o.[object_id] AS referenced_id , 
    o.name AS referenced_name, 
	  o.[object_id] AS referencing_id, 
	  o.name AS referencing_name,  
	  0 AS NestLevel
	FROM  sys.objects o 
  WHERE o.is_ms_shipped = 0 AND o.type = 'V'
    
  UNION ALL
    
  SELECT  r.name, d1.referenced_id,  
    OBJECT_NAME( d1.referenced_id) , 
    d1.referencing_id, 
    OBJECT_NAME( d1.referencing_id) , 
    NestLevel + 1
  FROM  sys.sql_expression_dependencies d1 
  -- !! RECURSION !!
  JOIN DepTree r 
    ON d1.referenced_id =  r.referencing_id
),
NestedLevels as (
  -- We only care about the most deeply nested cases for our view
  SELECT DISTINCT 
    name as ViewName,
    MAX(NestLevel) AS MaxNestLevel
  FROM DepTree
  GROUP BY name, referenced_id
)
SELECT 
  -- This EXEC updates the view to reflect any changes within the database
  --   So if a datatype changes in an underlying table it will be reflected down the view tree
  --   only after we have refreshed the refrencing views
  -- There N'' is needed because there are non-ascii characters in view names
  'EXEC sp_refreshview N''' + s.name + '.' + v.name + ''';' as query

FROM sys.views v

-- We can have views in multiples schemas
JOIN sys.schemas s on v.schema_id = s.schema_id
JOIN NestedLevels nl on v.name = nl.ViewName

-- This returns everything so it will be updated in the correct order
ORDER BY nl.MaxNestLevel ASC, v.modify_date ASC;


OPEN c_refresh_object
FETCH NEXT FROM c_refresh_object INTO @stmt_refresh_object
WHILE @@FETCH_STATUS = 0
  BEGIN
    print @stmt_refresh_object
    exec sp_executesql @stmt_refresh_object
    FETCH NEXT FROM c_refresh_object INTO @stmt_refresh_object
  END
CLOSE c_refresh_object
DEALLOCATE c_refresh_object
