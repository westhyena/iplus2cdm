SET NOCOUNT ON;

IF OBJECT_ID('$(StagingSchema).hira_map','U') IS NOT NULL
  DROP TABLE [$(StagingSchema)].[hira_map];

CREATE TABLE [$(StagingSchema)].[hira_map] (
  SOURCE_DOMAIN_ID    nvarchar(50)   NULL,
  LOCAL_CD1           nvarchar(100)  NULL,
  LOCAL_CD1_NM        nvarchar(500)  NULL,
  TARGET_CONCEPT_ID_1 int            NULL,
  TARGET_DOMAIN_ID    nvarchar(50)   NULL,
  VALID_START_DATE    datetime       NULL,
  VALID_END_DATE      datetime       NULL,
  INVALID_REASON      nvarchar(10)   NULL,
  SEQ                 int            NULL,
  SOURCE_CONCEPT_ID   int            NULL
);


