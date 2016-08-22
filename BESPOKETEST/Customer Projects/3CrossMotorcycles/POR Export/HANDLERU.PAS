unit HandlerU;

{ Hook Customisation Unit - Allows standard Enterprise behaviour to }
{                           be modified by calling code in the DLL  }

interface

Uses
  Math, ComObj, APIUtil, CustWinU, CustAbsU, Classes, Controls, PISecure
  , StrUtil, FileUtil, MathUtil, Types, Enterprise01_TLB, MiscUtil, IniFiles, POR3XPROC;

const
  sPlugInName = '3 X Export POR Plug-In';
  {$IFDEF EX600}
    sVersionNo = 'v6.00.001';
  {$ELSE}
    sVersionNo = 'v5.71.001';
  {$ENDIF}
  sINIFileName = 'POR3X.INI';

type
  TPINInfo = class
    Value : real;
    Currency : byte;
  end;

var
  iPORDaybookBtnId : byte = 0;

  { Following functions required to be Exported by Enterprise }
  Procedure InitCustomHandler(Var CustomOn : Boolean; CustomHandlers : TAbsCustomHandlers); Export;
  Procedure TermCustomHandler; Export;
  Procedure ExecCustomHandler(Const EventData : TAbsEnterpriseSystem); Export;

implementation

Uses
  TKUtil, Dialogs, SysUtils, ChainU, PIMisc, Forms, ETMiscU;

Const
  EventDisabled = 0;
  EventEnabled  = 1;

var
  bHookEnabled : boolean;

{ Called by Enterprise to initialise the Customisation }
Procedure InitCustomHandler(Var CustomOn : Boolean; CustomHandlers : TAbsCustomHandlers);
type
  THookPointRec = record
    WindowID : integer;
    HandlerID : integer;
  end;
const
  NO_OF_HOOK_POINTS = 1;
var
  iEID : byte;
  iHook, iPos : integer;
  slAboutText : TStringList;
  aHookPoints : array [1..NO_OF_HOOK_POINTS] of THookPointRec;
begin
  CustomOn := True;

  //Check Plug-In Security
  bHookEnabled := PICheckSecurity('EXCH3XPORX000200', 'ska$sdkj2S 3a d£', sPlugInName
  , sVersionNo + ' (DLL)', stSystemOnly, ptDLL, DLLChain.ModuleName);

  if bHookEnabled then begin

    With TAbsCustomHandlers01(CustomHandlers) Do Begin
      { Set About Message }
      slAboutText := TStringList.Create;
      PIMakeAboutText(sPlugInName, sVersionNo + ' (DLL)', slAboutText);
      for iPos := 0 to slAboutText.Count - 1 do AddAboutString(slAboutText[iPos]);

      // Detect if POR Daybook Custom button 1 is already in use.
      if (not HookPointEnabled(wiTransaction, 114)) then
        begin
          iPORDaybookBtnId := 114;
        end
      else begin
        // Detect if POR Daybook Custom button 2 is already in use.
        if (not HookPointEnabled(wiTransaction, 124)) then begin
          iPORDaybookBtnId := 124;
        end;{if}
      end;{if}

      // Custom Button  POR DayBook - POR Export
      aHookPoints[1].WindowID := wiTransaction;
      aHookPoints[1].HandlerID := iPORDaybookBtnId;

      // Enable Hooks
      For iHook := 1 to NO_OF_HOOK_POINTS do
      begin
        if aHookPoints[iHook].HandlerID > 0
        then SetHandlerStatus(aHookPoints[iHook].WindowID, aHookPoints[iHook].HandlerID
        , EventEnabled);
      end;{for}

      slAboutText.Free;
    End; { With }
  end;{if}

  { Call other Hook DLL's to get their customisation }
  DLLChain.InitCustomHandler(CustomOn, CustomHandlers);

End;

{ Called by Enterprise to End the Customisation }
Procedure TermCustomHandler;
Begin
  If Assigned(oToolkit) Then Begin
    // Close COM Toolkit and remove reference
    oToolkit.CloseToolkit;
    oToolkit := NIL;
  End; { If Assigned(oToolkit) }

  { Notify other Hook DLL's to Terminate }
  DLLChain.TermCustomHandler;

  { Put Shutdown Code Here }
End;

{ Called by Enterprise whenever a Customised Event happens }
Procedure ExecCustomHandler(Const EventData : TAbsEnterpriseSystem);
var
  iStatus, iPos : integer;
  sError, sContRef : string;
  slPINs : TStringList;

  function GetIniSettings : boolean;
  var
    TheInifile : TInifile;
    sSection : string;
    iCategory, iPos : integer;
  begin{GetIniSettings}
    Result := TRUE;
    TheInifile := TInifile.Create(IncludeTrailingPathDelimiter(EventData.Setup.ssDataPath)
    + sInifileName);
    with SetupRec do begin
      sPeugeotAccountCode  := TheInifile.ReadString('Settings','PeugeotAccountCode','80911907');

(*      with oToolkit do
      begin

        // Check GL Codes
        oToolkit.GeneralLedger.Index := glIdxCode;
        For iPos := GL_FIRSTCODE to GL_LASTCODE do
        begin
          if GeneralLedger.GetEqual(GeneralLedger.BuildCodeIndex(GLCodes[iPos])) <> 0
          then begin
            Result := FALSE;
            break;
          end;
        end;{for}

        // Check CostCentre
        oToolkit.CostCentre.Index := cdIdxCode;
        if oToolkit.CostCentre.GetEqual(oToolkit.CostCentre.BuildCodeIndex(sCostCentre)) <> 0
        then Result := FALSE;

        // Check Department
        oToolkit.Department.Index := cdIdxCode;
        if oToolkit.Department.GetEqual(oToolkit.Department.BuildCodeIndex(sDepartment)) <> 0
        then Result := FALSE;
      end;{with}*)
    end;{with}
    TheInifile.Free;
  end;{GetIniSettings}

  procedure ExportPOR(sOurRef, sFormat, sPath : string);
    var
      sFilename : string;

    procedure SuccessfulExport;
    begin{SuccessfulExport}
      MsgBox('The Purchase Order (' + sOurRef + ') has been successfully exported to : '#13#13
      + sFilename, mtInformation, [mbOK], mbOK, 'Finished');
    end;{SuccessfulExport}

    procedure ExportPeugeot(oPOR : ITransaction; sFilename : string);
    var
     iExportLine, iNoOfLines, iLine : integer;
    begin{ExportPeugeot}
      with oPOR do
      begin
        // Add up no of lines that we are exporting
        iNoOfLines := 0;
        For iLine := 1 to thLines.thLineCount do
        begin
          if not ZeroFloat(thLines.thLine[iLine].tlQty)
          then inc(iNoOfLines);
        end;{for}

        // Header Line
        AddLineToFile(PadString(psRight, 'CDPR', ' ', 4)                         // 1-4 File Type
        + PadString(psRight, 'E', ' ', 1)                                        // 5 Header
        + PadString(psRight, SetupRec.sPeugeotAccountCode, ' ', 8)               // 6-13 Account Code with Peugeot
        + PadString(psRight, Copy(oPOR.thOurRef,1,2)+Copy(oPOR.thOurRef,4,6), ' ', 8)    // 14-21 POR Ref
        + PadString(psRight, 'N', ' ', 1)                                        // 22 Franco Port Code
        + PadString(psLeft, '1', '0', 1)                                        // 23 Type of Order
        + PadString(psRight, oPOR.thDueDate, ' ', 8)                             // 24-31 Delivery Date
        + PadString(psRight, '', ' ', 25)                                        // 32-56 Special Address Name
        + PadString(psRight, '', ' ', 25)                                        // 57-81 Special Address Line 1
        + PadString(psRight, '', ' ', 25)                                        // 82-106 Special Address Line 2
        + PadString(psRight, '', ' ', 25)                                        // 107-131 Special Address Line 3
        + PadString(psRight, '', ' ', 25)                                        // 132-156 Special Address Line 4
        + PadString(psRight, '', ' ', 25)                                        // 157-181 Special Address Line 5
        + PadString(psRight, '', ' ', 10)                                        // 182-191 Special Address Postcode
        + PadString(psRight, '', ' ', 25)                                        // 192-216 Special Address Town
        + PadString(psRight, DateToStr8(Date), ' ', 8)                           // 217-224 Date of Export
        + PadString(psRight, TimeToStr6(Time), ' ', 6)                           // 225-230 Time of Export
        + PadString(psLeft, IntToStr(iNoOfLines), '0', 3)                       // 231-233 No Of Lines
        + PadString(psRight, '*', ' ', 1)                                        // 234 End of Header
        , sFilename);

        iExportLine := 0;
        For iLine := 1 to thLines.thLineCount do
        begin
          with thLines.thLine[iLine] do
          begin
            if not ZeroFloat(tlQty) then
            begin
              // TX Line
              Inc(iExportLine);
              AddLineToFile(PadString(psRight, 'CDPR', ' ', 4)                   // 1-4 File Type
              + PadString(psRight, 'D', ' ', 1)                                  // 5 Line
              + PadString(psRight, SetupRec.sPeugeotAccountCode, ' ', 8)         // 6-13 Account Code with Peugeot
              + PadString(psRight, Copy(oPOR.thOurRef,1,2)+Copy(oPOR.thOurRef,4,6), ' ', 8) // 14-21 POR Ref
              + PadString(psLeft, IntToStr(iExportLine), '0', 3)                 // 22-24 Line No
              + PadString(psRight, Copy(tlStockCode,3,8), ' ', 8)                // 25-32 Stock Code
              + PadString(psRight, Copy(tlDescr, 1, 30), ' ', 30)                // 33-62 Line Desc
              + PadString(psLeft, '1', '0', 5)                                   // 63-67 Packaging
              + PadString(psLeft, IntToStr(Round(tlQty)), '0', 5)                       // 68-72 Quantity
              + PadString(psLeft, '0', '0', 1)                                   // 73 Flag Promo
              + PadString(psLeft, '0', '0', 15)                                  // 74-88 Promo Price
              + PadString(psRight, '*', ' ', 1)                                  // 89 End of Line
              , sFilename);
            end;{if}
          end;{with}
        end;{for}
      end;{with}
      SuccessfulExport;
    end;{ExportPeugeot}

    procedure ExportSoftway(oPOR : ITransaction; sFilename : string);
    begin{ExportSoftway}
      MsgBox('The Softway format has not yet been implemented', mtWarning, [mbOK], mbOK, 'Softway Format');
    end;{ExportSoftway}

    procedure ExportTriumph(oPOR : ITransaction; sFilename : string);
    begin{ExportTriumph}
      MsgBox('The Triumph format has not yet been implemented', mtWarning, [mbOK], mbOK, 'Triumph Format');
    end;{ExportTriumph}

    procedure InvalidFormat;
    begin{InvalidFormat}
      MsgBox('The format code stored against UDF1 (' + sFormat + ') on the supplier record is not a valid format code.'#13#13
      + 'If you wish to export purchase orders from this supplier, you must modify this format code to be valid.'
      , mtWarning, [mbOK], mbOK, 'Invalid Format');
    end;{InvalidFormat}

  var
    iStatus : integer;

  begin{ExportPOR}
    if (Length(sFormat) <> 1) then
    begin
      InvalidFormat;
    end else
    begin
      if not DirectoryExists(sPath) then
      begin
        // Invalid Path
        MsgBox('The path stored against UDF2 (' + sPath + ') on the supplier record is not a valid path.'#13#13
        + 'If you wish to export purchase orders from this supplier, you must modify this path to be valid.'
        , mtWarning, [mbOK], mbOK, 'Invalid Path');
      end
      else
      begin
        // Set Filename
        sFilename := sPath + sOurRef + '_' + DateToStr8(Date) + '_' + TimeToStr6(Time) + '.TXT';

        // Get Transaction in Toolkit
        oToolkit.Transaction.Index := thIdxOurRef;
        iStatus := oToolkit.Transaction.GetEqual(oToolkit.Transaction.BuildOurRefIndex(sOurRef));
        if iStatus <> 0 then
        begin
          // Invalid POR
          MsgBox('The Purchase Order (' + sOurRef + ') does not exist in the database.'#13#13
          , mtError, [mbOK], mbOK, 'Invalid POR');
        end
        else
        begin
          Case sFormat[1] of
            'P' : ExportPeugeot(oToolkit.Transaction, sFilename);
            'S' : ExportSoftway(oToolkit.Transaction, sFilename);
            'T' : ExportTriumph(oToolkit.Transaction, sFilename);
            else InvalidFormat;
          end;{case}

        end;{if}
      end;{if}
    end;{if}
  end;{ExportPOR}

Begin
  if bHookEnabled then begin

    { Handle Hook Events here }
    With EventData Do Begin
      // A 'Hook Event' has occurred
      Case WinId Of
        wiTransaction : begin
          if HandlerId = iPORDaybookBtnId then
          begin
            // Export POR button pressed

            // Check TX Type
            if EventData.Transaction.thInvDocHed = cuPOR then
            begin

              if MsgBox('Are you sure you want to export this Purchase Order ? '#13#13
              + 'Purchase Order : ' + EventData.Transaction.thOurRef, mtConfirmation
              , [mbYes, mbNo], mbNo, 'Export POR') = mrYes then
              begin
                StartToolkit(EventData);
                GetIniSettings;

                ExportPOR(EventData.Transaction.thOurRef, Trim(UpperCase(EventData.Supplier.acUserDef1))
                , IncludeTrailingPathDelimiter(Trim(EventData.Supplier.acUserDef2)));

                // Check if the IniFile has sensible settings in it
{                if GetIniSettings then
                begin

                  if TXHasBeenReceived then
                  begin

                  end else
                  begin
                    MsgBox('This transaction does not have any lines with a received quanity.'#13#13
                    + 'You must receive this order before you can continue.', mtError
                    , [mbOK], mbOK, 'Received Quantity');
                  end;{if}
{                end else
                begin
                  MsgBox('The settings in ' + sINIFileName + ' have not been setup correctly.'#13#13
                  + 'You must configure this correctly before you can continue.', mtError
                  , [mbOK], mbOK, 'INI file setup');
                end;{if}

                oToolkit.CloseToolkit;
                oToolkit := nil;
              end;{if}
            end else
            begin
              MsgBox('The selected transaction is not a Purchase Order.'#13#13
              + 'You can only export PORs.', mtInformation
              , [mbOK], mbOK, 'Transaction Type');
            end;{if}
          end;{if}
        end;
      end;{case}
    end;{with}
  end;{if}

  { Pass onto other Hook DLL's }
  DLLChain.ExecCustomHandler(EventData);
End;

end.




PEUGEOT EXAMPLE FROM 3X
-----------------------
CDPRE8091190700033654N120080923                                                                                                                                                                                         20080916141306014*
CDPRD8091190700033654001L URGENTURGENT DHL CARRIAGE           00001000010000000000000000*
CDPRD8091190700033654002756819  CALIPER                       00001000010000000000000000*
CDPRD8091190700033654003766775  MAIN HARNESS                  00001000010000000000000000*
CDPRD8091190700033654004759913  LH/RH FORK TUBE               00001000010000000000000000*
CDPRD8091190700033654005768644B2HOLDER                        00001000030000000000000000*
CDPRD8091190700033654006733969  MAIN ROD                      00001000020000000000000000*
CDPRD8091190700033654007752409  HOSE                          00001000010000000000000000*
CDPRD8091190700033654008734278E9LH SIDE PANEL                 00001000020000000000000000*
CDPRD8091190700033654009754165  SEAL                          00001000020000000000000000*
CDPRD8091190700033654010758148  CYLINDER HEAD                 00001000010000000000000000*
CDPRD8091190700033654011758164  PISTON RING SET               00001000010000000000000000*
CDPRD8091190700033654012758159  PISTON                        00001000010000000000000000*
CDPRD8091190700033654013758163  CIRCLIP                       00001000020000000000000000*
CDPRD8091190700033654014L URGENTURGENT DHL CARRIAGE           00001000010000000000000000*


PEUGEOT EXAMPLE FROM THIS PROGRAM
---------------------------------
CDPRE80911907PO000565N120061219                                                                                                                                                                                         20081218150428014*
CDPRD80911907PO000565001LB-BA-PE100W Pearl Light Bulb, BA - 4 00001010000000000000000000*
CDPRD80911907PO000565002LB-BA-PE40W Pearl Light Bulb, BC - 4 P00001012000000000000000000*
CDPRD80911907PO000565003LB-SC-PE150W Pearl Light Bulb, SC - 4 00001013000000000000000000*
CDPRD80911907PO000565004LB-SC-PE40W Pearl Light Bulb, SC - 4 P00001011000000000000000000*
CDPRD80911907PO000565005LB-BA-PE150W Pearl Light Bulb, BC - 4 00001013000000000000000000*
CDPRD80911907PO000565006ND-B-INS20mm Black Conduit inspection 00001002000000000000000000*
CDPRD80911907PO000565007ND-BLK-225mm Black Conduit 3m length  00001007000000000000000000*
CDPRD80911907PO000565008-1000W-5Phillips Spotlight 1000W, 50 D00001000400000000000000000*
CDPRD80911907PO000565009-400W-60Phillips Spotlight 400W, 60 De00001002000000000000000000*
CDPRD80911907PO000565010-600W-50Phillips Spotlight 600W, 50 De00001000630000000000000000*
CDPRD80911907PO000565011ND-B-ANG25mm Black ConduitAngle Box   00001010000000000000000000*
CDPRD80911907PO000565012NS-PIR  PIR Sensor                    00001002320000000000000000*
CDPRD80911907PO000565013NS-PIR-MPIR Sensor and movement Sensor00001001000000000000000000*
CDPRD80911907PO000565014NS-PIR-SPIR Sensor and Smoket Sensor  00001000900000000000000000*
