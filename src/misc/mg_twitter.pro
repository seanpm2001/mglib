; docformat = 'rst'

;+
; Very simple Twitter client.
;
; :Todo:
;   Needs to add support for direct messages received, but must keep a list
;   of messages then to sort them by ID (since regular messages and direct
;   messages are returned via two different API calls).
;-

;= access properties

;+
; Get property values.
;
; :Private:
;
; :Keywords:
;   latest_id : out, optional, type=unsigned long64
;     identifier of the latest read tweet
;-
pro mgfftwitterstatuses::getProperty, latest_id=latestId
  compile_opt strictarr

  if (arg_present(latestId)) then latestId = self.latestId
end


;= parse XML

;+
; Called to process the opening of a tag.
;
; :Private:
;
; :Params:
;   uri : in, required, type=string
;     namespace URI
;   local : in, required, type=string
;     element name with prefix removed
;   qname : in, required, type=string
;     element name
;   attName : in, optional, type=strarr
;     names of attributes
;   attValue : in, optional, type=strarr
;     attribute values
;-
pro mgfftwitterstatuses::startElement, uri, local, qname, attname, attvalue
  compile_opt strictarr

  case strlowcase(qname) of
    'id': self.insideId = 1B
    'screen_name': self.insideScreenname = 1B
    'status': self.byUser = 0B
    'text': begin
        self.chars = ''
        self.insideText = 1B
        self.itemNumber++
      end
    else:
  endcase
end


;+
; Called to process the closing of a tag.
;
; :Private:
;
; :Params:
;   uri : in, required, type=string
;     namespace URI
;   local : in, required, type=string
;     element name with prefix removed
;   qname : in, required, type=string
;     element name
;-
pro mgfftwitterstatuses::endElement, uri, local, qname
  compile_opt strictarr

  case strlowcase(qname) of
    'id': self.insideId = 0B
    'screen_name': self.insideScreenname = 0B
    'text': self.insideText = 0B
    'status': begin
        isReply = strpos(self.chars, '@' + self.username) ge 0L
        tweet = mg_strwrap(self.author + ': ' + self.chars, indent=2)

        firstLine = tweet[0]
        strput, firstLine, '+', 0
        tweet[0] = firstLine

        print, mg_ansicode(mg_strmerge(tweet), red=isReply, green=self.byUser)
      end
    else:
  endcase
end


;+
; Called to process character data in an XML file.
;
; :Private:
;
; :Params:
;   chars : in, required, type=string
;     characters detected by parser
;-
pro mgfftwitterstatuses::characters, chars
  compile_opt strictarr

  if (self.insideText) then self.chars += chars
  if (self.insideScreenname) then begin
    if (chars eq self.username) then self.byUser = 1B
    self.author = chars
  endif
  if (self.insideId) then begin
    id = ulong64(chars)
    self.latestId >= id
  endif
end


;= lifecycle methods

;+
; Create twitter status object.
;
; :Private:
;
; :Returns:
;   1 for success, 0 otherwise
;
; :Keywords:
;   username : in, optional, type=string, default=''
;     Twitter username
;   _extra : in, optional, type=keywords
;     keywords to `IDLffXMLSAX::init`
;-
function mgfftwitterstatuses::init, username=username, _extra=e

  if (~self->IDLffXMLSAX::init(_extra=e)) then return, 0
  self.username = n_elements(username) eq 0L ? '' : username

  return, 1
end


;+
; Define instance variables.
;
; :Private:
;-
pro mgfftwitterstatuses__define
  compile_opt strictarr

  define = { MGffTwitterStatuses, inherits IDLffXMLSAX, $
             username: '', $
             itemNumber: 0B, $
             insideText: 0B, $
             insideId: 0B, $
             latestId: 0ULL, $
             insideScreenname: 0B, $
             byUser: 0B, $
             author: '', $
             chars: '' $
           }
end


;+
; Display tweets in Twitter timeline since last called.
;
; :Bugs:
;   no longer valid after Twitter API changes
;
; :Params:
;   username : in, required, type=string
;     Twitter username
;   password : in, required, type=string
;     Twitter password
;
; :Keywords:
;   count : in, optional, type=integer, default=20
;     number of tweets to show
;-
pro mg_twitter, username, password, count=count
  compile_opt strictarr

  catch, error
  if (error ne 0L) then begin
    catch, /cancel
    print, 'Fail-whale: there was a problem getting tweets'
    return
  endif

  prefs = obj_new('MGffPrefs', author_name='mgalloy', app_name='mg_twitter')
  sinceId = prefs->get('latest_id', found=found)
  since = found ? string(sinceId, '(%"&since_id=%d")') : ''

  _count = n_elements(count) gt 0L ? count[0] : 20L

  urlFormat = '(%"http://twitter.com/statuses/friends_timeline.xml?count=%d' + since + '")'
  userUrl = string(_count, format=urlFormat)

  if (n_elements(username) gt 0L) then prefs->set, 'username', username
  if (n_elements(password) gt 0L) then prefs->set, 'password', password

  _username = prefs->get('username', found=usernameFound)
  _password = prefs->get('password', found=passwordFound)

  if (~usernameFound && ~passwordFound) then begin
    obj_destroy, prefs
    message, 'username or password not found'
  endif

  url = obj_new('MGnetRequest', userUrl)
  url->addHeader, 'Authorization', $
                  'Basic ' + mg_base64encode(_username + ':' + _password)
  lines = url->get()
  obj_destroy, url

  url = obj_new('MGffTwitterStatuses', username=_username)
  url->parseFile, mg_strmerge(lines), /xml_string
  url->getProperty, latest_id=latestId
  obj_destroy, url

  if (latestId gt 0L) then prefs->set, 'latest_id', latestId

  obj_destroy, prefs
end
