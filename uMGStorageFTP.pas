unit uMGStorageFTP;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Masks, Vcl.Forms,
  System.IOUtils, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient,
  IdExplicitTLSClientServerBase, IdFTP, IdFTPList,
  uMGStorage;

  type

 TMGFTPConnection = class(TMGStorageService)
      fConnFTP: TIdFTP;
  protected
    procedure PropertiesChanged; override;
    procedure GetFilesEx(Path, Mask: String; List: TStringList; Recurse: Boolean);
    procedure FTPForceDirectories( Path: String );
  public
    constructor Create( ConnectionString: String );
    destructor Destroy; override;

    procedure DeleteFolder( Folder: String; Recursive: Boolean ); override;

    procedure Connect; override;
    procedure PutFile( Localfilename, DestStorageFilename: String ); override;
    procedure GetFile( Storagefilename, DestLocalFilename: String ); override;
    procedure DeleteFile( Storagefilename: String ); override;
    procedure RenameFile( StorageFilenameOld, StorageFilenameNew: String ); override;
    procedure CopyFile( StorageFilenameOld, StorageFilenameNew: String ); override;
    function FileExists( StorageFilename: String ): boolean; override;
    function CalcFileURL( StorageFilename: String ) : String; override;
    function GetFileList( Path, Mask: String; IncSubfolders: Boolean  ): integer; override;
  end;

implementation

{ TMGFTPConnection }

function TMGFTPConnection.CalcFileURL(StorageFilename: String): String;
begin
  AssertConnected;
  Result := 'ftp://' + fServer + EFP( '', StorageFilename, false, false  );
end;

procedure TMGFTPConnection.Connect;
begin
  fConnFTP.Connect;
  fConnected := true;
end;

procedure TMGFTPConnection.CopyFile(StorageFilenameOld,
  StorageFilenameNew: String);
var
  TmpLocal: String;
begin
  AssertConnected;
  // There is no copy in FTP.  It's a get and a put.  User be warned
  TmpLocal := System.IOUtils.TPath.GetTempFileName;
  try
    GetFile( EFP( '', StorageFilenameOld ), TmpLocal );
    PutFile( TmpLocal, EFP( '', StorageFilenameNew ) );
    System.SysUtils.DeleteFile( TmpLocal );
  except on E:Exception do
    begin
      System.SysUtils.DeleteFile( TmpLocal );
      RaiseCopyError( StorageFilenameOld, StorageFilenameNew );
    end;
  end;
end;

constructor TMGFTPConnection.Create( ConnectionString: String);
begin
  fConnFTP := TIdFTP.Create( nil );
  inherited;
end;

procedure TMGFTPConnection.DeleteFile(Storagefilename: String);
begin
  AssertConnected;
  if( self.FileExists( StorageFilename ) ) then
  begin
    try
      fConnFTP.Delete( EFP( '', StorageFilename ) );
    except on E:Exception do
      RaiseDeleteFileError( StorageFilename );
    end;
  end;
end;

function SortPathDepth( List: TStringList; Index1: Integer; Index2: Integer ):Integer;
var
  D1, D2: integer;
begin
  D1 := Length( List[Index1] ) - Length( StringReplace( List[Index1], '/', '', [rfReplaceAll] ) );
  D2 := Length( List[Index2] ) - Length( StringReplace( List[Index2], '/', '', [rfReplaceAll] ) );
  if( D1 > D2 ) then
    Result := -1
  else if( D1 < D2 ) then
    Result := 1
  else
    Result := 0;
end;


procedure TMGFTPConnection.DeleteFolder(Folder: String; Recursive: Boolean);
var
  ToDelete: TStringList;
  i: integer;
begin
  AssertConnected;
  if IsRootFolder(Folder) then
    RaiseDeleteFolderRootError;
  Folder := EFP( '', Folder, false, false );
  if( Not Recursive ) then
    fConnFTP.RemoveDir( Folder )
  else
  begin
    ToDelete := TStringList.Create;
    try
      GetFilesEx( Folder, '*', ToDelete, Recursive );
      for I := ToDelete.Count-1 downto 0 do
      begin
        if( ToDelete.Objects[i] = nil ) then
        begin
          fConnFTP.Delete( ToDelete[i] );
          ToDelete.Delete( i );
        end;
      end;
      ToDelete.CustomSort( SortPathDepth );
      for I := 0 to ToDelete.Count-1 do
          fConnFTP.RemoveDir( ToDelete[i] );
      fConnFTP.RemoveDir( Folder );
    finally
      FreeAndNil( ToDelete );
    end;

  end;


end;

destructor TMGFTPConnection.Destroy;
begin
  FreeAndNil( fConnFTP );
  inherited;
end;

procedure TMGFTPConnection.GetFile(Storagefilename,
  DestLocalFilename: String);
begin
  AssertConnected;
  try
    fConnFTP.Get( EFP( '', Storagefilename ), DestLocalFilename, true, false ) ;
  except on E:Exception do
    RaiseGetFileError( Storagefilename, DestLocalFilename );
  end;
end;

function TMGFTPConnection.FileExists(StorageFilename: String): boolean;
// It's tough: If you give a folder name, it's possible that it will list
// the contents of the folder.  The only way I've found is to look
// for files starting with filename, and hope the returned list isn't too
// large.  This avoids downloading an entire folder listing
// if checking for folder existance.
begin
  AssertConnected;
  Result := false;
  if( StorageFilename = '' ) then
    exit
  else
  begin
    begin
      try
        fTmpSL.Clear;
        fConnFTP.List( fTmpSL ,  EFP( '', StorageFilename, false, false ), false);
      except // Do nothing, so SL.Count will be zero
      end;
      Result := fTmpSL.Count > 0;
    end;
  end;
end;

procedure TMGFTPConnection.FTPForceDirectories(Path: String);
var
  P: Integer;
  TmpFolder: String;
begin
  TmpFolder := '';
  P := LastDelimiter( '/', Path );
  if P > 0 then
  begin
    Path := Copy( Path, 1, P-1 );  // Remove filename
    while Path <> '' do
    begin
      P := Pos( '/', Path );
      if( P > 0 ) then
      begin
        TmpFolder := TmpFolder + Copy( Path, 1, P );
        Path := Copy( Path, P+1 );
      end
      else
      begin
        TmpFolder := TmpFolder + Path;
        Path := '';
      end;
      try
        fConnFTP.MakeDir( TmpFolder );
      except
      end;
    end;
  end;
end;

function TMGFTPConnection.GetFileList(Path, Mask: String; IncSubfolders: Boolean): integer;
begin
  AssertConnected;
  fItemList.Clear;
  Path := EFP( '', Path, true, false );
  if( Path = '/' ) then
    Path := '';
  GetFilesEx( Path, Mask, nil, IncSubFolders );
  fItemList.Sort;
  Result := fItemList.Count;
end;


procedure TMGFTPConnection.GetFilesEx(Path, Mask: String; List: TStringList; Recurse: Boolean);
var
  SL: TStringList;
  i: integer;
begin
  SL := TStringList.Create;
  try
    try
      fConnFTP.List(SL, Path, true); // pass True instead to get more file details
    except on E:Exception do
      begin
      end;
    end;
    if( Path <> '' ) and (Path[Length( Path ) ] <> '/' ) then
      Path := Path + '/';
    for I := 0 to SL.Count-1 do
    begin
        if( fConnFTP.DirectoryListing[i].ItemType = ditFile ) then
        begin
            if( List <> nil ) then
              List.AddObject ( Path + fConnFTP.DirectoryListing[i].FileName, nil)  // Files are nil
            else
            if( FileMatches( fConnFTP.DirectoryListing[i].FileName, Mask ) ) then
              fItemList.Add( TMGListItem.Create( '/' + Path + fConnFTP.DirectoryListing[i].FileName,
                fConnFTP.DirectoryListing[i].Size,
                fConnFTP.DirectoryListing[i].ModifiedDate, mgitFile), fCaseSensitive);
            SL[i] := '';
        end
        else if( fConnFTP.DirectoryListing[i].ItemType = ditDirectory ) then
        begin
          if( List <> nil ) then
          begin
            SL[i] := fConnFTP.DirectoryListing[i].FileName;
            List.AddObject ( Path + fConnFTP.DirectoryListing[i].FileName, Pointer(1) );  // Folders are not nil
          end
          else
          begin
            SL[i] := fConnFTP.DirectoryListing[i].FileName+'/';
            if( FileMatches( fConnFTP.DirectoryListing[i].FileName, Mask ) ) then
              fItemList.Add( TMGListItem.Create( '/' + Path + fConnFTP.DirectoryListing[i].FileName,
                fConnFTP.DirectoryListing[i].Size,
                fConnFTP.DirectoryListing[i].ModifiedDate, mgitFolder), fCaseSensitive );
          end;
        end;
    end;
    if( Recurse ) then
    begin
      for I := 0 to SL.Count-1 do
      begin
        if( SL[i] <> '' ) then
        begin
          GetFilesEx( Path + SL[i], Mask, List, Recurse );
        end;
      end;
    end;


  finally
    SL.Free;
  end;

end;

procedure TMGFTPConnection.PropertiesChanged;
begin
  if( fConnFTP.Connected ) then
    fConnFTP.Disconnect;
  fConnFTP.Username := fProperties.Values['Username'];
  fConnFTP.Password := fProperties.Values['Password'];
  fConnFTP.HOST := fProperties.Values['Server'];
  fCaseSensitive := SameText(fProperties.Values['CaseSensitive'],'yes');
end;

procedure TMGFTPConnection.RenameFile(StorageFilenameOld,
  StorageFilenameNew: String);
begin
  AssertConnected;
  try
    fConnFTP.Rename( EFP('', StorageFilenameOld ),  EFP('', StorageFilenameNew ) );
  except on E:Exception do
    RaiseRenameError( StorageFilenameOld, StorageFilenameNew );
  end;
end;

procedure TMGFTPConnection.PutFile(Localfilename, DestStorageFilename: String);
begin
  AssertConnected;
  AssertLocal( Localfilename );
  try
    DestStorageFilename := EFP( '', DestStorageFilename, false, false );
    FTPForceDirectories( DestStorageFilename );
    fConnFTP.Put( LocalFilename, DestStorageFilename ) ;
  except on E:Exception do
    RaisePutFileError( DestStorageFilename );
  end;
end;

end.
