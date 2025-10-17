SET NOCOUNT ON;
BEGIN TRY
  BEGIN TRAN;
  DELETE FROM [$(CdmSchema)].[condition_occurrence];
  DELETE FROM [$(CdmSchema)].[drug_exposure];
  DELETE FROM [$(CdmSchema)].[measurement];
  DELETE FROM [$(CdmSchema)].[visit_occurrence];
  DELETE FROM [$(CdmSchema)].[observation_period];
  DELETE FROM [$(CdmSchema)].[person];
  COMMIT;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  THROW;
END CATCH
