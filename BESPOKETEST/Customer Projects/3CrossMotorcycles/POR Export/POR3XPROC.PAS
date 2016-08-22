unit POR3XPROC;

{ nfrewer440 17:10 08/12/2003: Disabled Byte Alignment in Delphi 6.0 }
{$ALIGN 1}  { Variable Alignment Disabled }


interface
uses
  StrUtil, CustABSU, Enterprise01_TLB, {TFile,}Classes, StdCtrls;

const
  GL_FIRSTCODE = 1;
  GL_CAT = 0;
//  GL_FREIGHT = 1;
//  GL_INSURANCE = 2;
//  GL_INTEREST = 3;
//  GL_DUTY = 4;
//  GL_CONTAINER = 5;
//  GL_HMC = 6;
//  GL_RHD = 7;
//  GL_LASTCODEBUTONE = 7;
  GL_ROUNDING = 8;
  GL_LASTCODE = GL_ROUNDING;
  GL_LASTCODEBUTONE = GL_ROUNDING-1;

//  aNoteDescs : array[GL_FIRSTCODE..GL_LASTCODEBUTONE] of string = ('FREIGHT=', 'INSURANCE='
//  , 'INTEREST=', 'DUTY=', 'CONTAINER=', 'HMC=', 'RH&D=');
//  aDescs : array[GL_FIRSTCODE..GL_LASTCODEBUTONE] of string = ('Freight', 'Insurance'
//  , 'Interest', 'Duty', 'Container', 'HMC', 'RH&D');
  sApportioned = 'Apportioned: See Matching Information';
  iApportionedNoteLineNo = GL_LASTCODE;

type
  TCompanyRec = Record
    Name : string[45];
    Code : string[6];
    Path : string[100];
  end;

{  TCompanyInfo = Class
    CompanyRec : TCompanyRec;
  end;}

  TSetupRec = Record
    sPeugeotAccountCode : string;
  end;

  TCompanyInfo = Class
    CompanyRec : TCompanyRec;
    bCurrentCompany : boolean;
  end;{with}

  TCurrencyInfo = Class
    CurrencyNo : integer;
  end;{with}

  procedure StartToolkit(LEventData : TAbsEnterpriseSystem);
  procedure FillCurrencyCombo(cmbCurrency : TComboBox; iDefaultCcy : integer);
//  function GetCustNameFromCode(sCustCode : string) : string;
//  function GetProdNameFromCode(sStockCode : string) : string;
//  procedure InitToolkit(cmbCompany : TComboBox);
  function ConvertCurrency(rValue : real; iFromCcy, iToCcy : integer) : real;
  function GetStockWeight(sStockCode : string) : double;

var
  oToolkit : IToolkit;
  CompanyRec : TCompanyRec;
  SetupRec : TSetupRec;

implementation
uses
  MathUtil, MiscUtil, SecCodes, Dialogs, BTConst, SysUtils, BTUtil, APIUtil, COMObj;

procedure StartToolkit(LEventData : TAbsEnterpriseSystem);
var
  a, b, c : LongInt;
  FuncRes : integer;

begin{StartToolkit}
  if oToolkit = nil then
  begin
    // Create COM Toolkit object
    oToolkit := CreateOLEObject('Enterprise01.Toolkit') as IToolkit;

    // Check it created OK
    If Assigned(oToolkit) Then Begin
      With oToolkit Do Begin
        EncodeOpCode(97, a, b, c);
        oToolkit.Configuration.SetDebugMode(a, b, c);

        oToolkit.Configuration.OverwriteTransactionNumbers := TRUE;

  //      oToolkit.Configuration.AutoSetTransCurrencyRates := TRUE;
        oToolkit.Configuration.AutoSetTransCurrencyRates := FALSE;

        // Open Default Company
        oToolkit.Configuration.DataDirectory := LEventData.Setup.ssDataPath;
        FuncRes := OpenToolkit;

        // Check it opened OK
        If (FuncRes = 0) then {DoUpdates}
        else begin
          // Error opening Toolkit - display error
          ShowMessage ('The following error occurred opening the Toolkit:-'#13#13
          + QuotedStr(oToolkit.LastErrorString));
        end;{if}

      End; { With OToolkit }

    End { If Assigned(oToolkit) }
    Else
      // Failed to create COM Object
      ShowMessage ('Cannot create COM Toolkit instance');
  end;{if}
end;{StartToolkit}

procedure FillCurrencyCombo(cmbCurrency : TComboBox; iDefaultCcy : integer);
var
  iSelected, iPos : integer;
  sCurrChar : string;
  CurrencyInfo : TCurrencyInfo;
begin
  ClearList(cmbCurrency.Items);
  iSelected := 0;
//  cmbCurrency.Items.Add('(no currency selected)');
  For iPos := 1 to oToolkit.SystemSetup.ssMaxCurrency do begin
    if Trim(oToolkit.SystemSetup.ssCurrency[iPos].scDesc) <> '' then begin
      // get correct currency char
      sCurrChar := oToolkit.SystemSetup.ssCurrency[iPos].scSymbol;
      if sCurrChar = #156 then sCurrChar := '£';

      CurrencyInfo := TCurrencyInfo.Create;
      CurrencyInfo.CurrencyNo := iPos;
      cmbCurrency.Items.AddObject(IntToStr(iPos) + ' - ' + oToolkit.SystemSetup.ssCurrency[iPos].scDesc
      + ' (' + sCurrChar + ')', CurrencyInfo);

      if iPos = iDefaultCcy then iSelected := cmbCurrency.Items.count -1;
    end;
  end;{for}

  if cmbCurrency.Items.Count > 0 then cmbCurrency.Itemindex := iSelected;
end;
(*
function GetCustNameFromCode(sCustCode : string) : string;
begin
  with oToolkit.Customer do begin
    Index := acIdxCode;
    if GetEqual(BuildCodeIndex(sCustCode)) = 0
    then Result := acCompany
    else Result := '';
  end;{with}
end;

function GetProdNameFromCode(sStockCode : string) : string;
begin
  Result := '';
  with oToolkit.Stock do begin
    Index := stIdxCode;
    if GetEqual(BuildCodeIndex(sStockCode)) = 0
    then begin
      if (stType in [stTypeProduct, stTypeDescription, stTypeBillOfMaterials])
      then begin
        Result := stDesc[1];
      end;
    end;{if}
  end;{with}
end;

procedure InitToolkit(cmbCompany : TComboBox);
var
  iSelectIndex, iPos : integer;
  CompanyInfo : TCompanyInfo;
  a, b, c : LongInt;
begin{InitToolkit}
  // Create COM Toolkit object
  oToolkit := CreateOLEObject('Enterprise01.Toolkit') as IToolkit;

  // Check it created OK
  If Assigned(oToolkit) Then Begin

    EncodeOpCode(97, a, b, c);
    oToolkit.Configuration.SetDebugMode(a, b, c);
    oToolkit.Configuration.AutoSetTransCurrencyRates := TRUE;

    if (cmbCompany <> nil) then
    begin
      iSelectIndex := 0;
      For iPos := 1 to oToolkit.Company.cmCount do begin
        CompanyInfo := TCompanyInfo.Create;
        CompanyInfo.CompanyRec.Path := Trim(oToolkit.Company.cmCompany[iPos].coPath);
        CompanyInfo.CompanyRec.Name := Trim(oToolkit.Company.cmCompany[iPos].coName);
        CompanyInfo.CompanyRec.Code := Trim(oToolkit.Company.cmCompany[iPos].coCode);
        cmbCompany.Items.AddObject(oToolkit.Company.cmCompany[iPos].coName, CompanyInfo);

        if oToolkit.Enterprise.enRunning
        and ((uppercase(CompanyInfo.CompanyRec.Path)) = (uppercase(Trim(oToolkit.Enterprise.enCompanyPath))))
        then iSelectIndex := iPos -1;
      end;{for}

      // select current or first company
      cmbCompany.ItemIndex := iSelectIndex;
  //    cmbCompanyChange(cmbCompany);
      cmbCompany.OnChange(cmbCompany);;
    end;{if}

  End { If Assigned(oToolkit) }
  Else
    // Failed to create COM Object
    ShowMessage ('Cannot create COM Toolkit instance');
end;{InitToolkit}
*)
function ConvertCurrency(rValue : real; iFromCcy, iToCcy : integer) : real;
begin
  if iFromCcy = iToCcy then
  begin
    Result := rValue;
  end else
  begin
    Result := oToolkit.Functions.entConvertAmount(rValue
    ,iFromCcy, iToCcy, oToolkit.SystemSetup.ssCurrencyRateType);
  end;{if}
end;

function GetStockWeight(sStockCode : string) : double;
var
  iStatus : integer;
begin
  oToolkit.Stock.Index := stIdxCode;
  iStatus := oToolkit.Stock.GetEqual(oToolkit.Stock.BuildCodeIndex(sStockCode));
  if iStatus = 0 then Result := oToolkit.Stock.stIntrastat.stSSDPurchaseUnitWeight
  else Result := 0;
end;


initialization
  oToolkit := nil;

finalization

end.
