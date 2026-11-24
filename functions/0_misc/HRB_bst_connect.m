function dbDir = HRB_bst_connect(dbDirCfg, protocolName, log, opt)
% HRB_BST_CONNECT - Single entry point to Brainstorm for every HRB_bst_* module:
%   1) resolve the DB folder (default <pwd>/brainstorm_db)
%   2) start BST in SERVER mode if not running (headless; 'nogui' needs X11)
%   3) switch DB if needed
%   4) activate the protocol (create it only if CreateIfMissing=true)
%
% Usage:
%   dbDir = HRB_bst_connect(config.BrainstormDbDir, protocolName, log)
%   dbDir = HRB_bst_connect(config.BrainstormDbDir, config.ProtocolName, log, ...
%                           CreateIfMissing=true, UseDefaultAnat=config.UseDefaultAnat)
%
% Inputs:
%   dbDirCfg     - [string] BST DB folder; "" = <pwd>/brainstorm_db
%   protocolName - [string] protocol to activate
%   log          - logger object
% Name-value:
%   CreateIfMissing - [logical] create the protocol if absent (default false: error)
%   UseDefaultAnat  - [logical] for a new protocol (default true)
%   Timeout         - [s] BST start-up timeout (default 120)
% Output:
%   dbDir - [char] DB folder in use
%
% Authors: Ettore Napoli, University of Bologna, 2026
arguments
    dbDirCfg string
    protocolName string
    log
    opt.CreateIfMissing (1,1) logical = false
    opt.UseDefaultAnat  (1,1) logical = true
    opt.Timeout         (1,1) double  = 120
end

% 1) DB folder
if strlength(dbDirCfg) > 0
    dbDir = char(dbDirCfg);
else
    dbDir = fullfile(pwd, 'brainstorm_db');
end
if ~exist(dbDir, 'dir'), mkdir(dbDir); end
log.info(sprintf("Brainstorm DB: %s", dbDir));

% 2) Start Brainstorm (server mode)
bstWorking = false;
if brainstorm('status')
    try, bst_get('BrainstormDbDir'); bstWorking = true; catch, end
end
if ~bstWorking
    log.info("Starting Brainstorm (server mode)...");
    brainstorm server;
    t = tic;
    while toc(t) < opt.Timeout
        try, bst_get('BrainstormDbDir'); bstWorking = true; break; catch, pause(1); end
    end
    if ~bstWorking
        error("HRB:BrainstormTimeout", "Brainstorm failed to initialize within %d seconds.", opt.Timeout);
    end
    log.info("Brainstorm initialized successfully.");
end

% 3) Switch DB if needed
currentDbDir = bst_get('BrainstormDbDir');
if ~strcmpi(strip(currentDbDir, 'right', filesep), strip(dbDir, 'right', filesep))
    log.info(sprintf("Switching BST DB: '%s' -> '%s'", currentDbDir, dbDir));
    bst_set('BrainstormDbDir', dbDir);
    gui_brainstorm('UpdateProtocolsList');
end

% 4) Protocol
iProtocol = bst_get('Protocol', char(protocolName));
if isempty(iProtocol)
    gui_brainstorm('UpdateProtocolsList');          % on disk but not in memory
    iProtocol = bst_get('Protocol', char(protocolName));
end
if isempty(iProtocol)
    if ~opt.CreateIfMissing
        error("HRB:ProtocolNotFound", "Protocol '%s' not found. Run HRB_bst_import first.", protocolName);
    end
    log.info(sprintf("Creating new protocol: %s", protocolName));
    gui_brainstorm('CreateProtocol', char(protocolName), double(opt.UseDefaultAnat), 0);
    iProtocol = bst_get('Protocol', char(protocolName));
    if isempty(iProtocol)
        error("HRB:ProtocolCreateFailed", "Could not create protocol '%s'.", protocolName);
    end
end
gui_brainstorm('SetCurrentProtocol', iProtocol);
log.info(sprintf("Protocol '%s' set as current.", protocolName));
end