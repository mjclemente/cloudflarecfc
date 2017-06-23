/*
  Copyright (c) 2017, Matthew Clemente, John Berquist

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
component output="false" displayname="Cloudflare.cfc"  {

  variables.utcBaseDate = dateAdd( "l", createDate( 1970,1,1 ).getTime() * -1, createDate( 1970,1,1 ) );
  variables.integerFields = [ ];
  variables.numericFields = [ ];
  variables.timestampFields = [ ];
  variables.booleanFields = [ "purge_everything" ];
  variables.arrayFields = [ "files" ];
  variables.dictionaryFields = {};

  public any function init( string authEmail, string authKey, string baseUrl = "https://api.cloudflare.com/client/v4/", numeric httpTimeout = 60, boolean includeRaw = false, string zone_identifier = '' ) {

    structAppend( variables, arguments );
    return this;
  }

  //ZONES
  public struct function getZones() {
    return apiCall( "zones", setupParams({}), "get" );
  }

  public struct function purgeFiles( any urls = [], string zone_identifier = variables.zone_identifier ) {

    var requestBody = { "purge_everything" : true };

    if ( !isArray( urls ) ) {
      if ( urls.len() )
        requestBody = { "files" : [ urls ] };
    } else if ( urls.len() ) {
      requestBody = { "files" : urls };
    }

    return apiCall( "zones/#zone_identifier#/purge_cache", setupParams( requestBody ), "delete" );
  }



  // PRIVATE FUNCTIONS
  private struct function apiCall( required string path, array params = [ ], string method = "get" )  {

    var fullApiPath = variables.baseUrl & path;
    var requestStart = getTickCount();

    var apiResponse = makeHttpRequest( urlPath = fullApiPath, params = params, method = method );

    var result = { "api_request_time" = getTickCount() - requestStart, "status_code" = listFirst( apiResponse.statuscode, " " ), "status_text" = listRest( apiResponse.statuscode, " " ) };
    if ( variables.includeRaw ) {
      result[ "raw" ] = { "method" = ucase( method ), "path" = fullApiPath, "params" = serializeJSON( params ), "response" = apiResponse.fileContent };
    }

    try {
      structAppend(  result, deserializeJSON( apiResponse.fileContent ), true );
    } catch ( any e ) {
      writeDump( var='#fullApiPath#', format='html', abort='false' );
      writeDump( var='#params#', format='html', abort='false' );
      writeDump( var='#method#', format='html', abort='false' );
      writeDump( var='#apiResponse#', format='html', abort='true' );
      // writeOutput(apiResponse.filecontent);
      // abort;
    }

    parseResult( result );
    return result;
  }

  private any function makeHttpRequest( required string urlPath, required array params, required string method ) {

    var result = {};
    var requestBody = {};

    for ( var param in params ) {
      requestBody[ "#param.name.lcase()#" ] = param.value;
    }

    var javaUrl = CreateObject( "java", "java.net.URL" ).init( urlPath );
    var req = javaUrl.openConnection();
    req.setRequestMethod( method.ucase() );
    req.setDoOutput( true );
    req.setRequestProperty( "User-Agent", "cloudflare.cfc" );
    req.setRequestProperty( "Content-Type", "application/json" );
    req.setRequestProperty( "X-Auth-Email", variables.authEmail );
    req.setRequestProperty( "X-Auth-Key", variables.authKey );

    if ( params.len() ) {
      var outputStream = req.getOutputStream();
      outputStream.write( javaCast( "string" , serializeJson( requestBody ) ).getBytes( "UTF-8" ) );
      outputStream.close();
    }

    var responseCode = req.getResponseCode();
    var responseMessage = req.getResponseMessage();

    if ( responseCode == req.HTTP_OK ) {
      var inputStream = req.getInputStream();
    } else {
      var inputStream = req.getErrorStream();
    }

    var bufferedReader = createObject("java", "java.io.BufferedReader" ).init( createObject( "java", "java.io.InputStreamReader" ).init( inputStream ) );
    var stringBuilder = createObject( "java", "java.lang.StringBuilder" ).init();

    var line = bufferedReader.readLine();
    while( !isNull( line ) ){
      stringBuilder.append( line );
      line = bufferedReader.readLine();
    }
    var headerFields = req.getHeaderFields().entrySet().toArray();

    var responseHeader = {};
    for ( var entry in headerFields ) {

      if ( !isNull( entry.getKey() ) ) {
        responseHeader[ "#entry.getKey()#" ] = entry.getValue().len() == 1
          ? entry.getValue()[1]
          : entry.getValue();
        } else {
          responseHeader[ "Http_Version" ] = entry.getValue()[1].listFirst( ' ' );
        }

    }

    req.disconnect();

    result[ "fileContent" ] = stringBuilder.toString();
    result[ "statusCode" ] = responseCode & ' ' & responseMessage;
    result[ "responseHeader" ] = responseHeader;
    return result;
  }

  private array function setupParams( required struct params ) {
    var filteredParams = { };
    var paramKeys = structKeyArray( params );
    for ( var paramKey in paramKeys ) {
      if ( structKeyExists( params, paramKey ) && !isNull( params[ paramKey ] ) ) {
        filteredParams[ paramKey ] = params[ paramKey ];
      }
    }

    return parseDictionary( filteredParams );
  }

  private array function parseDictionary( required struct dictionary, string name = '', string root = '' ) {
    var result = [ ];
    var structFieldExists = structKeyExists( variables.dictionaryFields, name );

    // validate required dictionary keys based on variables.dictionaries
    if ( structFieldExists ) {
      for ( var field in variables.dictionaryFields[ name ].required ) {
        if ( !structKeyExists( dictionary, field ) ) {
          throwError( "'#name#' dictionary missing required field: #field#" );
        }
      }
    }

    // special tag handling -- tags have a 3 key limit
    if ( name == "tag" ) {
      if ( arrayLen( structKeyArray( dictionary ) ) > 3 ) {
        throwError( "There can be a maximum of 3 keys in a tag struct." );
      }
    }

    for ( var key in dictionary ) {

      // confirm that key is a valid one based on variables.dictionaries
      if ( structFieldExists && !( arrayFindNoCase( variables.dictionaryFields[ name ].required, key ) || arrayFindNoCase( variables.dictionaryFields[ name ].optional, key ) ) ) {
        throwError( "'#name#' dictionary has invalid field: #key#" );
      }

      var fullKey = len( root ) ? root & ':' & lcase( key ) : lcase( key );
      if ( isStruct( dictionary[ key ] ) ) {
        for ( var item in parseDictionary( dictionary[ key ], key, fullKey ) ) {
          arrayAppend( result, item );
        }
      } else if ( isArray( dictionary[ key ] ) ) {
        arrayAppend( result, parseArray( dictionary[ key ], key, fullKey ) );
      } else {
        // note: metadata struct is special - no validation is done on it
        arrayAppend( result, { name = fullKey, value = getValidatedParam( key, dictionary[ key ], true ) } );
      }

    }
    return result;
  }

  private struct function parseArray( required array list, string name = '', string root = '' ) {
    var result = [ ];
    var index = 0;

    var arrayFieldExists = arrayFindNoCase( variables.arrayFields, name );

    if ( !arrayFieldExists ) {
      throwError( "'#name#' is not an allowed list variable." );
    }

    for ( var item in list ) {
      if ( isStruct( item ) ) {
        var fullKey = len( root ) ? root & "[" & index & "]" : name & "[" & index & "]";
        for ( var item in parseDictionary( item, '', fullKey ) ) {
          arrayAppend( result, item );
        }
        ++index;
      } else {
        var fullKey = len( root ) ? root : name;
        arrayAppend( result, getValidatedParam( name, item ) );
      }
    }

    return {
      "name" : name,
      "value" : result
    };
  }

  private any function getValidatedParam( required string paramName, required any paramValue, boolean validate = true ) {
    // only simple values
    if ( !isSimpleValue( paramValue ) ) throwError( "'#paramName#' is not a simple value." );

    // integer
    if ( arrayFindNoCase( variables.integerFields, paramName ) ) {
      if ( !isInteger( paramValue ) ) {
        throwError( "field '#paramName#' requires an integer value" );
      }
      return paramValue;
    }
    // numeric
    if ( arrayFindNoCase( variables.numericFields, paramName ) ) {
      if ( !isNumeric( paramValue ) ) {
        throwError( "field '#paramName#' requires a numeric value" );
      }
      return paramValue;
    }

    // boolean
    if ( arrayFindNoCase( variables.booleanFields, paramName ) ) {
      return ( paramValue ? "true" : "false" );
    }

    // timestamp
    if ( arrayFindNoCase( variables.timestampFields, paramName ) ) {
      return parseUTCTimestampField( paramValue, paramName );
    }

    // default is string
    return paramValue;
  }

  private void function parseResult( required struct result ) {
    var resultKeys = structKeyArray( result );
    for ( var key in resultKeys ) {
      if ( structKeyExists( result, key ) && !isNull( result[ key ] ) ) {
        if ( isStruct( result[ key ] ) ) parseResult( result[ key ] );
        if ( isArray( result[ key ] ) ) {
          for ( var item in result[ key ] ) {
            if ( isStruct( item ) ) parseResult( item );
          }
        }
        if ( arrayFindNoCase( variables.timestampFields, key ) ) result[ key ] = parseUTCTimestamp( result[ key ] );
      }
    }
  }

  private any function parseUTCTimestampField( required any utcField, required string utcFieldName ) {
    if ( isInteger( utcField ) ) return utcField;
    if ( isDate( utcField ) ) return getUTCTimestamp( utcField );
    throwError( "utc timestamp field '#utcFieldName#' is in an invalid format" );
  }

  private numeric function getUTCTimestamp( required date dateToConvert ) {
    return dateDiff( "s", variables.utcBaseDate, dateToConvert );
  }

  private date function parseUTCTimestamp( required numeric utcTimestamp ) {
    return dateAdd( "s", utcTimestamp, variables.utcBaseDate );
  }

  private boolean function isInteger( required any varToValidate ) {
    return ( isNumeric( varToValidate ) && isValid( "integer", varToValidate ) );
  }

  private string function encodeurl( required string str ) {
    return replacelist( urlEncodedFormat( str, "utf-8" ), "%2D,%2E,%5F,%7E", "-,.,_,~" );
  }

  private void function throwError( required string errorMessage, string detail = "" ) {
    throw( type = "Cloudflare", message = "(cloudflare.cfc) " & errorMessage, detail = detail );
  }

}