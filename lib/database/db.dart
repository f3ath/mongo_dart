class Db{
  String databaseName;
  ServerConfig serverConfig;
  Connection connection;
  validateDatabaseName(String dbName) {
    if(dbName.length === 0) throw "database name cannot be the empty string";  
    var invalidChars = [" ", ".", "\$", "/", "\\"];
    for(var i = 0; i < invalidChars.length; i++) {
      if(dbName.indexOf(invalidChars[i]) != -1) throw new Exception("database names cannot contain the character '${invalidChars[i]}'");
    }
  }    
  Db.local(this.databaseName){
     if (serverConfig === null) {
      serverConfig = new ServerConfig();
     }
    connection = new Connection(serverConfig);
  }
  Db(String uriString){
    var uri = new Uri.fromString(uriString);
    if (uri.scheme != 'mongodb') {
      throw 'Invalid scheme in uri: $uriString';
    }
    serverConfig = new ServerConfig();
    serverConfig.host = uri.domain;
    serverConfig.port = uri.port;
    if (serverConfig.port == null || serverConfig.port == 0){
      serverConfig.port = 27017;
    }
    if (uri.userInfo != '') {
      var userInfo = uri.userInfo.split(':');
      if (userInfo.length != 2) {
        throw 'Неверный формат поля userInfo: $uri.userInfo';
      }
      serverConfig.userName = userInfo[0];
      serverConfig.password = userInfo[1];
    }
    if (uri.path != '') {
      databaseName = uri.path.replaceAll('/','');
    }
    connection = new Connection(serverConfig);
  }
  DbCollection collection(String collectionName){
      return new DbCollection(this,collectionName);
  }
  Future<MongoReplyMessage> executeQueryMessage(MongoMessage queryMessage){
    return connection.query(queryMessage);
  }  
  executeMessage(MongoMessage message){
    connection.execute(message);
  }    
  Future<bool> open(){
    Completer completer = new Completer();
    initBsonPlatform();
    if (connection.connected){
      connection.close();
      connection = new Connection(serverConfig);
    }
//    print("${serverConfig.host} ${serverConfig.port} ${serverConfig.userName} ${serverConfig.password}" );
    connection.connect().then((v) {
      if (serverConfig.userName === null) {
        completer.complete(v);
      }
      else {
        authenticate(serverConfig.userName,serverConfig.password).then((v) {
          completer.complete(v);
        });
      }
    });
    return completer.future;
  }
  Future<Map> executeDbCommand(MongoMessage message){
      Completer<Map> result = new Completer();
      //print("executeDbCommand.message = ${message}");
      connection.query(message).then((replyMessage){
        //print("replyMessage = ${replyMessage}");
        //print("replyMessage.documents = ${replyMessage.documents}");
        
        String errMsg;
        if (replyMessage.documents.length == 0) {
          errMsg = "Error executing Db command, Document length 0 $replyMessage";
          print("Error: $errMsg");
          var m = new Map();
          m["errmsg"]=errMsg;
          result.complete(m);
        } else  if (replyMessage.documents[0]["ok"] == 1.0){
          result.complete(replyMessage.documents[0]);
        } else {
          errMsg = "Error executing Db command";
          if (replyMessage.documents[0].containsKey("errmsg")){
            errMsg = replyMessage.documents[0]["errmsg"];
          }
          print("Error: $errMsg");
          result.complete(replyMessage.documents[0]);
        }         
      });
    return result.future;        
  }
  Future<bool> dropCollection(String collectionName){
    Completer completer = new Completer();
    collectionsInfoCursor(collectionName).toList().then((v){
      if (v.length == 1){
        executeDbCommand(DbCommand.createDropCollectionCommand(this,collectionName))
          .then((res)=>completer.complete(res));
        } else{
          completer.complete(true);
        }  
    });    
    return completer.future;    
  }
  Future<Map> drop(){
    Completer completer = new Completer();
    executeDbCommand(DbCommand.createDropDatabaseCommand(this))
      .then((res)=>completer.complete(res));
    return completer.future;    
  }
  
  removeFromCollection(String collectionName, [Map selector = const {}]){
    connection.execute(new MongoRemoveMessage("$databaseName.$collectionName", selector));    
  }    
  
  Future<Map> getLastError(){    
    return executeDbCommand(DbCommand.createGetLastErrorCommand(this));
  }
  Future<Map> getNonce(){    
    return executeDbCommand(DbCommand.createGetNonceCommand(this));
  }

  Future<Map> wait(){
    return getLastError();
  }
  void close(){
//    print("closing db");
    connection.close();
  }
  
  Cursor collectionsInfoCursor([String collectionName]) {
    Map selector = {};
    // If we are limiting the access to a specific collection name
    if(collectionName !== null){
      selector["name"] = "${this.databaseName}.$collectionName";
    }  
    // Return Cursor
      return new Cursor(this, new DbCollection(this, DbCommand.SYSTEM_NAMESPACE_COLLECTION), selector);      
  }

  Future<bool> authenticate(String userName, String password){
    Completer completer = new Completer();
    getNonce().chain((msg) {
      var nonce = msg["nonce"];
      var command = DbCommand.createAuthenticationCommand(this,userName,password,nonce);
      serverConfig.password = '***********';
      return executeDbCommand(command);
    }).
    then((res)=>completer.complete(res["ok"] == 1));
    return completer.future;
  }
}