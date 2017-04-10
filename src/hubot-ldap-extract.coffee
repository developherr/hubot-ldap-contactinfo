# Description
#   Fetch information from an ldap server
#
# Configuration:
#   LDAP_URL - the URL to the LDAP server
#   LDAP_BIND_DN - bind DN used for LDAP connection
#   LDAP_BIND_SECRET - bind password used for LDAP connection
#   LDAP_SEARCH_BASE_DN - search base for contact information
#   LDAP_SEARCH_FILTER - search filter to be used, use {{searchTerm}} as placeholder for the user's search query
#   LDAP_RESULT_TPL - Handlebars template to be used to present matching information to the user (can use helpers from npm handlebards-helpers package + 'any' helper )
#   LDAP_TLSMODE - plain|starttls|tls
#   LDAP_CA_CERT - CA cert when using tls|starttls
#   LDAP_LISTENING_TRIGGER - the keyword to listen to in hubot conversations (can also be set to be a regular expression)
#
# Commands:
#   hubot directory <search> - Find ldap entries matching the given search query
#

LDAP = require 'ldapjs'
Q = require 'q'
any = require 'any'
Handlebars = require 'handlebars'
HandlebarsHelpers = require 'handlebars-helpers'

robot = null

Handlebars.registerHelper 'any', (value, search, options)->
  if( any value, search)
    return options.fn(this)

ldapURL = process.env.LDAP_URL or "ldap://127.0.0.1:1389"
tlsMode = process.env.LDAP_TLSMODE or "plain"
caCert = process.env.LDAP_CA_CERT or ""
bindDn = process.env.LDAP_BIND_DN or "cn=root"
bindSecret = process.env.LDAP_BIND_SECRET or "secret"
baseDn = process.env.LDAP_SEARCH_BASE_DN or "o=myhost"
searchFilter = process.env.LDAP_SEARCH_FILTER or "(&(objectclass=person)(cn=*{{searchTerm}}*))"
resultTpl = Handlebars.compile process.env.LDAP_RESULT_TPL or "{{cn}}", {helpers: HandlebarsHelpers()}
trigger = process.env.LDAP_LISTENING_TRIGGER or "directory"





opts = {
  url: ldapURL
}

if tlsMode == "tls"
  opts['cas'] = [caCert]

client = LDAP.createClient opts


startTLSIfConfigured = () ->
  deferred = Q.defer()

  if tlsMode == "starttls" && !client._starttls
    tlsOpts = {
      ca: [caCert]
    }

    client.starttls tlsOpts, [], (err, res) ->
      if err
        deferred.reject err

      deferred.resolve true
  else
    deferred.resolve true

  return deferred.promise

searchLdap = (searchTerm) ->
  deferred = Q.defer()

  startTLSIfConfigured()
  .fail (err) ->

    deferred.reject err
  .then ->

    client.bind bindDn, bindSecret, (err) ->

      if err
        deferred.reject err

      opts = {
        filter: searchFilter.replace "{{searchTerm}}", searchTerm
        scope: 'sub'
        paged: false
      }

      client.search baseDn, opts, (err, res) ->
        if err
          deferred.reject err

        entries = []

        res.on 'error', (err) ->
          deferred.reject err

        res.on 'searchEntry', (entry) ->
          entries.push entry.object

        res.on 'end', (result) ->

          setTimeout ->
            deferred.resolve entries
          ,0

  return deferred.promise


formatResult = (res) ->
  try
    rendered = resultTpl res
  catch err
    console.log err
    rendered = "Sorry, I can't display this result because of a faulty template (#{err})."

  return rendered


module.exports = (currentRobot) ->
  robot = currentRobot

  robot.respond ///#{trigger} (.+)///i, (msg) ->
    query = msg.match[msg.match.length - 1].trim()

    searchResult = searchLdap query

    searchResult
      .then (fEntries) ->

        if Object.keys(fEntries).length == 0
          msg.reply "Sorry, I can't find any entries matching your search \"#{query}\""
        else
          results = []
          numDisplayResults = Math.min 5, fEntries.length

          for i in [0..numDisplayResults]
            results.push formatResult(fEntries[i])

          msg.reply results.join("\n\n").trim()
      .catch (err) ->
        console.log err
        msg.reply "Sorry, I can't search the directory at the moment."
