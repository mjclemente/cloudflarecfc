/**
* cloudflarecfc
* Copyright 2017-2020  Matthew J. Clemente, John Berquist
* Licensed under MIT (https://mit-license.org)
*/
component displayname="cloudflarecfc"  {

  variables._cloudflarecfc_version = '0.0.0';

  public any function init(
    string authKey = '',
    string authEmail = '',
    string baseUrl = "https://api.cloudflare.com/client/v4",
    boolean includeRaw = false ) {

    structAppend( variables, arguments );

    //map sensitive args to env variables or java system props
    var secrets = {
      'authKey': 'CLOUDFLARE_AUTH_KEY',
      'authEmail': 'CLOUDFLARE_AUTH_EMAIL'
    };
    var system = createObject( 'java', 'java.lang.System' );

    for ( var key in secrets ) {
      //arguments are top priority
      if ( variables[ key ].len() ) continue;

      //check environment variables
      var envValue = system.getenv( secrets[ key ] );
      if ( !isNull( envValue ) && envValue.len() ) {
        variables[ key ] = envValue;
        continue;
      }

      //check java system properties
      var propValue = system.getProperty( secrets[ key ] );
      if ( !isNull( propValue ) && propValue.len() ) {
        variables[ key ] = propValue;
      }
    }

    //declare file fields to be handled via multipart/form-data **Important** this is not applicable if payload is application/json
    variables.fileFields = [];

    return this;
  }

  /**
  * https://api.cloudflare.com/#zone-list-zones
  * @hint List, search, sort, and filter your zones
  */
  public struct function listZones( struct filters = {} ) {
    var params = filters;
    if( filters.isEmpty() ) {
      params = arguments.copy();
      params.delete( 'filters' );
    }
    return apiCall( 'GET', '/zones', params );
  }

  /**
  * @hint Convenience function that delegates to listZones().
  */
  public struct function getZoneByName( required string name ) {
    var filters = { name = name };
    return listZones( filters );
  }

  /**
  * https://api.cloudflare.com/#zone-purge-all-files
  * @hint All resources in Cloudflare's cache for the zone should be removed.
  */
  public struct function purgeAllFiles( required string zoneId ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );
    var payload = { "purge_everything" : true };
    return apiCall( 'POST', '/zones/#zoneIdentifier#/purge_cache', {}, payload );
  }

  /**
  * https://api.cloudflare.com/#zone-purge-files-by-url
  * @hint Granularly remove one or more files from Cloudflare's cache by specifying URLs.
  */
  public struct function purgeFilesByUrl( required string zoneId, required any files ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );
    var payload = { "files" : [] };

    if ( !isArray( files ) )
        payload.files.append( files );
    else
      payload.files.append( files, true );

    return apiCall( 'POST', '/zones/#zoneIdentifier#/purge_cache', {}, payload );
  }

  /**
  * https://api.cloudflare.com/#dns-records-for-a-zone-list-dns-records
  * @hint List, search, sort, and filter a zones' DNS records.
  */
  public struct function listDnsRecords( required string zoneId, struct filters = {} ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );
    var params = filters;
    if( filters.isEmpty() ) {
      params = arguments.copy();
      params.delete( 'filters' );
      params.delete( 'zoneId' );
    }
    return apiCall( 'GET', '/zones/#zoneIdentifier#/dns_records', params );
  }

  /**
  * @hint Convenience function that delegates to listDnsRecords().
  */
  public struct function getDnsRecordsByName( required string zoneId, required string name ) {
    var filters = { name = name };
    return listDnsRecords( zoneId = zoneId, filters = filters );
  }

  /**
  * https://api.cloudflare.com/#dns-records-for-a-zone-create-dns-record
  * @hint Create a new DNS record for a zone. See the record object definitions for required attributes for each record type
  */
  public struct function createDnsRecord( required string zoneId, struct record = {} ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );

    var payload = record;
    if( record.isEmpty() ) {
      payload = arguments.copy();
      payload.delete( 'record' );
      payload.delete( 'zoneId' );
    }

    return apiCall( 'POST', '/zones/#zoneIdentifier#/dns_records', {}, payload );
  }

  /**
  * https://api.cloudflare.com/#dns-records-for-a-zone-update-dns-record
  * @hint Create an existing DNS record for a zone. See the record object definitions for required attributes for each record type
  */
  public struct function updateDnsRecord( required string zoneId, required string recordId, struct record = {} ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );
    var recordIdentifier = normalizeDnsRecordIdentifier( zoneId, recordId );

    var payload = record;
    if( record.isEmpty() ) {
      payload = arguments.copy();
      payload.delete( 'record' );
      payload.delete( 'recordId' );
      payload.delete( 'zoneId' );
    }

    return apiCall( 'PUT', '/zones/#zoneIdentifier#/dns_records/#recordIdentifier#', {}, payload );
  }

  /**
  * https://api.cloudflare.com/#dns-records-for-a-zone-delete-dns-record
  * @hint Delete a DNS record
  */
  public struct function deleteDnsRecord( required string zoneId, required string recordId ) {
    var zoneIdentifier = normalizeZoneIdentifier( zoneId );
    var recordIdentifier = normalizeDnsRecordIdentifier( zoneId, recordId );
    return apiCall( 'DELETE', '/zones/#zoneIdentifier#/dns_records/#recordIdentifier#' );
  }

  /**
  * https://api.cloudflare.com/#getting-started-resource-ids
  * @hint Checks the ID for validity, based on the docs: a 32-byte string of hex characters ([a-f0-9]).
  */
  private boolean function isValidIdentifier( required string id ) {
    var regex = '^[a-f0-9]{32,32}$';
    return refind( regex, id );
  }

  private string function normalizeZoneIdentifier( required string zoneId ) {
    var identifier = zoneId;
    if( !isValidIdentifier( identifier ) ) {
      var zones = getZoneByName( identifier ).data.result;
      if( zones.len() == 1 )
        identifier = zones[1].id;
    }
    return identifier;
  }

  private string function normalizeDnsRecordIdentifier( required string zoneId, required string recordId ) {
    var identifier = recordId;
    if( !isValidIdentifier( identifier ) ) {
      var records = getDnsRecordsByName( zoneId = zoneId, name = recordId ).data.result;
      if( records.len() == 1 )
        identifier = records[1].id;
    }
    return identifier;
  }

  // PRIVATE FUNCTIONS
  private struct function apiCall(
    required string httpMethod,
    required string path,
    struct queryParams = { },
    any payload = '',
    struct headers = { } )  {

    var fullApiPath = variables.baseUrl & path;
    var requestHeaders = getBaseHttpHeaders();
    requestHeaders.append( headers, true );

    var requestStart = getTickCount();
    var apiResponse = makeHttpRequest( httpMethod = httpMethod, path = fullApiPath, queryParams = queryParams, headers = requestHeaders, payload = payload );

    var result = {
      'responseTime' = getTickCount() - requestStart,
      'statusCode' = listFirst( apiResponse.statuscode, " " ),
      'statusText' = listRest( apiResponse.statuscode, " " ),
      'headers' = apiResponse.responseheader
    };

    var parsedFileContent = {};

    // Handle response based on mimetype
    var mimeType = apiResponse.mimetype ?: requestHeaders[ 'Content-Type' ];

    if ( mimeType == 'application/json' && isJson( apiResponse.fileContent ) ) {
      parsedFileContent = deserializeJSON( apiResponse.fileContent );
    } else if ( mimeType.listLast( '/' ) == 'xml' && isXml( apiResponse.fileContent ) ) {
      parsedFileContent = xmlToStruct( apiResponse.fileContent );
    } else {
      parsedFileContent = apiResponse.fileContent;
    }

    //can be customized by API integration for how errors are returned
    //if ( result.statusCode >= 400 ) {}

    //stored in data, because some responses are arrays and others are structs
    result[ 'data' ] = parsedFileContent;

    if ( variables.includeRaw ) {
      result[ 'raw' ] = {
        'method' : ucase( httpMethod ),
        'path' : fullApiPath,
        'params' : parseQueryParams( queryParams ),
        'payload' : parseBody( payload ),
        'response' : apiResponse.fileContent
      };
    }

    return result;
  }

  private struct function getBaseHttpHeaders() {
    return {
      'Accept' : 'application/json',
      'Content-Type' : 'application/json',
      'X-Auth-Key' : '#variables.authKey#',
      'X-Auth-Email' : '#variables.authEmail#',
      'User-Agent' : 'cloudflarecfc/#variables._cloudflarecfc_version# (ColdFusion)'
    };
  }

  private any function makeHttpRequest(
    required string httpMethod,
    required string path,
    struct queryParams = { },
    struct headers = { },
    any payload = ''
  ) {
    var result = '';

    var fullPath = path & ( !queryParams.isEmpty()
      ? ( '?' & parseQueryParams( queryParams, false ) )
      : '' );

    var requestHeaders = parseHeaders( headers );

    cfhttp( url = fullPath, method = httpMethod,  result = 'result' ) {

      if ( isJsonPayload( headers ) ) {

        var requestPayload = parseBody( payload );
        if ( isJSON( requestPayload ) )
          cfhttpparam( type = "body", value = requestPayload );

      } else if ( isFormPayload( headers ) ) {

        headers.delete( 'Content-Type' ); //Content Type added automatically by cfhttppparam

        for ( var param in payload ) {
          if ( !variables.fileFields.contains( param ) )
            cfhttpparam( type = 'formfield', name = param, value = payload[ param ] );
          else
            cfhttpparam( type = 'file', name = param, file = payload[ param ] );
        }

      }

      //handled last, to account for possible Content-Type header correction for forms
      var requestHeaders = parseHeaders( headers );
      for ( var header in requestHeaders ) {
        cfhttpparam( type = "header", name = header.name, value = header.value );
      }

    }
    return result;
  }

  /**
  * @hint convert the headers from a struct to an array
  */
  private array function parseHeaders( required struct headers ) {
    var sortedKeyArray = headers.keyArray();
    sortedKeyArray.sort( 'textnocase' );
    var processedHeaders = sortedKeyArray.map(
      function( key ) {
        return { name: key, value: trim( headers[ key ] ) };
      }
    );
    return processedHeaders;
  }

  /**
  * @hint converts the queryparam struct to a string, with optional encoding and the possibility for empty values being pass through as well
  */
  private string function parseQueryParams( required struct queryParams, boolean encodeQueryParams = true, boolean includeEmptyValues = true ) {
    var sortedKeyArray = queryParams.keyArray();
    sortedKeyArray.sort( 'text' );

    var queryString = sortedKeyArray.reduce(
      function( queryString, queryParamKey ) {
        var encodedKey = encodeQueryParams
          ? encodeUrl( queryParamKey.lcase() )
          : queryParamKey.lcase();
        if ( !isArray( queryParams[ queryParamKey ] ) ) {
          var encodedValue = encodeQueryParams && len( queryParams[ queryParamKey ] )
            ? encodeUrl( queryParams[ queryParamKey ] )
            : queryParams[ queryParamKey ];
        } else {
          var encodedValue = encodeQueryParams && ArrayLen( queryParams[ queryParamKey ] )
            ?  encodeUrl( serializeJSON( queryParams[ queryParamKey ] ) )
            : queryParams[ queryParamKey ].toList();
          }
        return queryString.listAppend( encodedKey & ( includeEmptyValues || len( encodedValue ) ? ( '=' & encodedValue ) : '' ), '&' );
      }, ''
    );

    return queryString.len() ? queryString : '';
  }

  private string function parseBody( required any body ) {
    if ( isStruct( body ) || isArray( body ) )
      return serializeJson( body );
    else if ( isJson( body ) )
      return body;
    else
      return '';
  }

  private string function encodeUrl( required string str, boolean encodeSlash = true ) {
    var result = replacelist( urlEncodedFormat( str, 'utf-8' ), '%2D,%2E,%5F,%7E', '-,.,_,~' );
    if ( !encodeSlash ) result = replace( result, '%2F', '/', 'all' );

    return result;
  }

  /**
  * @hint helper to determine if body should be sent as JSON
  */
  private boolean function isJsonPayload( required struct headers ) {
    return headers[ 'Content-Type' ] == 'application/json';
  }

  /**
  * @hint helper to determine if body should be sent as form params
  */
  private boolean function isFormPayload( required struct headers ) {
    return arrayContains( [ 'application/x-www-form-urlencoded', 'multipart/form-data' ], headers[ 'Content-Type' ] );
  }

  /**
  *
  * Based on an (old) blog post and UDF from Raymond Camden
  * https://www.raymondcamden.com/2012/01/04/Converting-XML-to-JSON-My-exploration-into-madness/
  *
  */
  private struct function xmlToStruct( required any x ) {

    if ( isSimpleValue( x ) && isXml( x ) )
      x = xmlParse( x );

    var s = {};

    if ( xmlGetNodeType( x ) == "DOCUMENT_NODE" ) {
      s[ structKeyList( x ) ] = xmlToStruct( x[ structKeyList( x ) ] );
    }

    if ( structKeyExists( x, "xmlAttributes" ) && !structIsEmpty( x.xmlAttributes ) ) {
      s.attributes = {};
      for ( var item in x.xmlAttributes ) {
        s.attributes[ item ] = x.xmlAttributes[ item ];
      }
    }

    if ( structKeyExists( x, 'xmlText' ) && x.xmlText.trim().len() )
      s.value = x.xmlText;

    if ( structKeyExists( x, "xmlChildren" ) ) {

      for ( var xmlChild in x.xmlChildren ) {
        if ( structKeyExists( s, xmlChild.xmlname ) ) {

          if ( !isArray( s[ xmlChild.xmlname ] ) ) {
            var temp = s[ xmlChild.xmlname ];
            s[ xmlChild.xmlname ] = [ temp ];
          }

          arrayAppend( s[ xmlChild.xmlname ], xmlToStruct( xmlChild ) );

        } else {

          if ( structKeyExists( xmlChild, "xmlChildren" ) && arrayLen( xmlChild.xmlChildren ) ) {
              s[ xmlChild.xmlName ] = xmlToStruct( xmlChild );
           } else if ( structKeyExists( xmlChild, "xmlAttributes" ) && !structIsEmpty( xmlChild.xmlAttributes ) ) {
            s[ xmlChild.xmlName ] = xmlToStruct( xmlChild );
          } else {
            s[ xmlChild.xmlName ] = xmlChild.xmlText;
          }

        }

      }
    }

    return s;
  }

}