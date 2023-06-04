unit MainFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math,  FMX.Clipboard, FMX.Platform,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types,
  FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, FMX.StdCtrls,
  FMX.Controls3D;

const
  SBoxSize = 256;


type
  TSBox = array[0..SBoxSize-1] of Byte;

type
  TComplex = record
    Re: Double;
    Im: Double;
  end;

  TComplexArray = array[0..SBoxSize-1] of TComplex;


type
  TfrmMain = class(TForm)
    btnGenerate: TButton;
    GroupBox1: TGroupBox;
    GroupBox2: TGroupBox;
    memoRaw: TMemo;
    memoHex: TMemo;
    btnCopyA: TButton;
    btnCopyB: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    procedure btnGenerateClick(Sender: TObject);
    procedure btnCopyAClick(Sender: TObject);
    procedure btnCopyBClick(Sender: TObject);
  private
    function CalculateNonlinearity(const B: TSBox; n: Integer): Double;
    function GenerateSBox: TSBox;
  public
    Memo: TMemo;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}


(*
For the 2 functions below, I used :
- Fast Walsh-Hadamard Transform by Luis Villasenor to generate nonlinearity : https://github.com/lvillasen
- Efficient Dynamic S-Box Generation Using Linear Trigonometric Transformation for Security Applications paper (10.1109/ACCESS.2021.3095618) published July 8, 2021 and supported by Texas A&M University-San Antonio
https://ieeexplore.ieee.org/stamp/stamp.jsp?arnumber=9477572
*)


procedure TfrmMain.btnCopyAClick(Sender: TObject);
var
  uClipBoard : IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, uClipBoard) then
    uClipBoard.SetClipboard(memoRaw.Text);
end;

procedure TfrmMain.btnCopyBClick(Sender: TObject);
var
  uClipBoard : IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, uClipBoard) then
    uClipBoard.SetClipboard(memoHex.Text);
end;

procedure TfrmMain.btnGenerateClick(Sender: TObject);
var
  SBox: TSBox;
  i, j: Integer;
  strBuildRawLine, strBuildHexLine: string;
  OriginalCursor: IFMXCursorService;
begin
  try
    if TPlatformServices.Current.SupportsPlatformService(IFMXCursorService) then
      OriginalCursor := TPlatformServices.Current.GetPlatformService(IFMXCursorService) as IFMXCursorService;
    if Assigned(OriginalCursor) then
    begin
      Cursor := OriginalCursor.GetCursor;
      OriginalCursor.SetCursor(crHourGlass);
    end;

    try
      strBuildRawLine := '';
      strBuildHexLine := '';

      SBox := GenerateSBox;

      try
        Memo := TMemo.Create(Self);        // Memo.Parent := Self;          // Memo.Lines.Clear;
        for i := Low(SBox) to High(SBox) do
          Memo.Lines.Add(IntToStr(SBox[i]));

        memoRaw.Lines.Clear;
        memoHex.Lines.Clear;
        for j := 0 to Memo.Lines.Count - 1 do
        begin
          strBuildRawLine := strBuildRawLine + Trim(Memo.Lines[j]) + ',';
          strBuildHexLine := strBuildHexLine + '$' + IntToHex(StrToInt(Trim(Memo.Lines[j])), 8) + ','; //strBuildHexLine := strBuildHexLine + IntToHex(StrToInt(Trim(Memo.Lines[j])), 2) + ',';
        end;

        Delete(strBuildRawLine, Length(strBuildRawLine), 1);
        memoRaw.Lines.Add(strBuildRawLine);

        Delete(strBuildHexLine, Length(strBuildHexLine), 1);
        memoHex.Lines.Add(strBuildHexLine);
      finally
        Memo.Free;
      end;
    except
      on E: Exception do
        ShowMessage('An error occurred: ' + E.Message);
    end;
  finally
    OriginalCursor.SetCursor(Cursor);
  end;
end;



function TfrmMain.CalculateNonlinearity(const B: TSBox; n: Integer): Double;
var
  Wmax: Integer;
  A: TComplexArray;
  C: TComplexArray;
  qbit, j: Integer;
  bit_parity: Integer;
  isq2: Double;
begin
  Wmax := 0;

  // Set initial value of array A
  FillChar(A[0], SBoxSize * SizeOf(TComplex), 0);

  isq2 := 1 / Sqrt(2);

  for qbit := 0 to n-1 do
  begin
    FillChar(C[0], SBoxSize * SizeOf(TComplex), 0);

    for j := 0 to SBoxSize-1 do
    begin
      if B[j] <> 0 then
      begin
        bit_parity := (j shr qbit) and 1;

        if bit_parity = 0 then
        begin
          C[j].Re := C[j].Re + isq2 * B[j];
          C[j or (1 shl qbit)].Re := C[j or (1 shl qbit)].Re + isq2 * B[j];
        end
        else if bit_parity = 1 then
        begin
          C[j and not (1 shl qbit)].Re := C[j and not (1 shl qbit)].Re + isq2 * B[j];
          C[j].Re := C[j].Re - isq2 * B[j];
        end;
      end;
    end;

    // Copy C to A for the next iteration
    for j := 0 to SBoxSize-1 do
      A[j] := C[j];
  end;

  // Find the maximum value based on the transformed array C
  for j := 0 to SBoxSize-1 do
  begin
    if Abs(C[j].Re) > Wmax then
      Wmax := Round(Abs(C[j].Re));
  end;

(*
The "Invalid floating point operation" error occurs when the expression inside the Sqrt function, Power(2, n) - Wmax, results in a negative value.
The Sqrt function does not accept negative values, which caused an error here.
To handle this situation, I added the following validation to ensure that the expression inside the Sqrt function is always non-negative.
One approach is to check if the calculated value, Wmax, is greater than or equal to Power(2, n). If it is, set the result of the Sqrt function to 0.
With this change, if the value of Wmax is greater than or equal to Power(2, n), the Result will be set to 0.
*)

  if Wmax >= Power(2, n) then
    Result := 0
  else
    Result := Sqrt(Power(2, n) - Wmax);
end;



function TfrmMain.GenerateSBox: TSBox;
const
  n = 8; // for n × n S-box
  //AVal: Byte = 1;
  //CVal: Byte = 1;
var
  S: TSBox;
  B: TComplexArray;
  F: TSBox;
  V, g, h, Loc: Integer;
  R1, R2, R3, R4, R5, R6: Integer;
  NL1, NL2: Double;
  Temp: Byte;
  X: Double;
  AVal, CVal: Byte; // Updated: Move AVal and CVal inside the function
begin
  Randomize; // Initialize random number generator

  AVal := Random(256); // Updated: Generate random AVal
  CVal := Random(256); // Updated: Generate random CVal

  // Preliminary 8 × 8 S-box generation
  X := 0.5; // Set initial value of X
  h := 0;
  while h <= SBoxSize-1 do
  begin
    R1 := (AVal + h) * Round(X);
    B[h].Re := System.Cos(R1 * h + CVal);
    B[h].Im := 0;
    if X > 0.5 then
      X := X * X
    else
      X := X * 1.75;
    Inc(h);
  end;

  for h := 0 to SBoxSize - 1 do
  begin
    g := Random(SBoxSize);
    Temp := S[h];
    S[h] := S[g];
    S[g] := Temp;
  end;

  // Final S-box generation based on nonlinearity improvisation plan
  g := 0;
  while g <= SBoxSize-1 do
  begin
    // Find minimum value in B and its location
    Loc := 0;
    for h := 0 to SBoxSize-1 do
    begin
      if B[h].Re < B[Loc].Re then
        Loc := h;
    end;

    F[g] := Loc;
    B[Loc].Re := 111;
    B[Loc].Im := 0;
    Inc(g);
  end;

  // Perform nonlinearity-based improvement
  NL1 := CalculateNonlinearity(F, n);
  V := 1;

  while V <= 65535 do
  begin
    R1 := (AVal * V + CVal) mod 257;
    R2 := (CVal * V + AVal) mod 257;
    R3 := (AVal * 1000 + V);
    R4 := (CVal * 1000 + V);
    R5 := (R1 + Round(X * V));
    R6 := (R2 + Round(X * V));
    h := Abs(Round(R3 * System.Cos(R5))) mod SBoxSize;
    Loc := Abs(Round(R4 * System.Cos(R6))) mod SBoxSize;

    // Swap values F[h] and F[Loc]
    Temp := F[h];
    F[h] := F[Loc];
    F[Loc] := Temp;

    NL2 := CalculateNonlinearity(F, n);
    if NL2 > NL1 then
    begin
      NL1 := NL2;
    end
    else
    begin
      // Swap values F[h] and F[Loc] back if NL2 is not greater than NL1
      Temp := F[h];
      F[h] := F[Loc];
      F[Loc] := Temp;
    end;

    Inc(V);
  end;

  Result := F;
end;


initialization
  ReportMemoryLeaksOnShutdown := True;



end.
