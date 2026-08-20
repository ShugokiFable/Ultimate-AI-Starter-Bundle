unit SkyrimForgeReportRecords;

var RecordCount: Integer;

function Initialize: Integer;
begin
  RecordCount := 0;
  Result := 0;
end;

function Process(e: IInterface): Integer;
begin
  Inc(RecordCount);
  AddMessage('SKYRIM_FORGE_RECORD signature=' + Signature(e) + ' formid=' + IntToHex(FixedFormID(e), 8) + ' editorid=' + EditorID(e));
  Result := 0;
end;

function Finalize: Integer;
begin
  AddMessage('SKYRIM_FORGE_REPORT_RECORDS records=' + IntToStr(RecordCount));
  Result := 0;
end;

end.
