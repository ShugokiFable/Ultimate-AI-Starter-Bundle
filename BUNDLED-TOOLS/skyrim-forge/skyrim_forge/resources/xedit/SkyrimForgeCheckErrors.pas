unit SkyrimForgeCheckErrors;

var
  ErrorCount: Integer;
  RecordCount: Integer;

function Walk(aIndent: Integer; aElement: IInterface): Boolean;
var
  ErrorText: string;
  i: Integer;
begin
  Result := False;
  ErrorText := Check(aElement);
  if ErrorText <> '' then begin
    Inc(ErrorCount);
    Result := True;
    AddMessage(StringOfChar(' ', aIndent * 2) + Name(aElement) + ' -> ' + ErrorText);
  end;
  for i := ElementCount(aElement) - 1 downto 0 do
    Result := Walk(aIndent + 1, ElementByIndex(aElement, i)) or Result;
end;

function Initialize: Integer;
begin
  ErrorCount := 0;
  RecordCount := 0;
  Result := 0;
end;

function Process(e: IInterface): Integer;
begin
  Inc(RecordCount);
  Walk(0, e);
  Result := 0;
end;

function Finalize: Integer;
begin
  AddMessage('SKYRIM_FORGE_CHECK_ERRORS errors=' + IntToStr(ErrorCount) + ' records=' + IntToStr(RecordCount));
  if ErrorCount > 0 then
    Result := 1
  else
    Result := 0;
end;

end.
