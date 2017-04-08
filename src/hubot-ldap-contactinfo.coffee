# Description
#   Fetch contact information from an ldap server
#
# Configuration:
#   LDAP_URL - the URL to the LDAP server
# Commands:
#   hubot what roles does <user> have - Find out what roles a user has
#   hubot what roles do I have - Find out what roles you have
#   hubot refreh roles
#
# Notes:
#   * returns bool true or false
#

LDAP = require 'ldapjs'
Q = require 'q'
Milk = require 'milk'
robot = null



ldapURL = process.env.LDAP_URL or "ldap://127.0.0.1:1389"
ldapBindDn = process.env.LDAP_BIND_DN or "cn=root"
ldapBindSecret = process.env.LDAP_BIND_SECRET or "secret"
baseDn = process.env.LDAP_SEARCH_BASE_DN or "o=myhost"
searchFilter = process.env.LDAP_SEARCH_FILTER or "(&(objectclass=person)(cn=*{{searchTerm}}*))"
mustacheTpl = process.env.MUSTACHE_TPL or "{{cn}}"

client = LDAP.createClient {
  url: ldapURL
}


searchLdap = (searchTerm) ->
  deferred = Q.defer()

  client.bind ldapBindDn, ldapBindSecret, (err) ->

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



formatContact = (contact) ->
  #console.log contact
  return Milk.render(mustacheTpl, contact)


module.exports = (currentRobot) ->
  robot = currentRobot

  robot.respond /contact (.+)/i, (msg) ->
    sContact = msg.match[1].trim()

    searchLdap sContact
      .fail (err) ->
        console.error err
        msg.reply "Sorry, I can't search for contact information at the moment."
      .then (fContacts) ->

        if Object.keys(fContacts).length == 0
          msg.reply "Sorry, I can't find any contact matching your search \"#{sContact}\""
        else
          results = []
          numDisplayResults = Math.min 5, fContacts.length

          for i in [0..numDisplayResults]
            fContact = fContacts[i]
            #console.log formatContact(fContact)
            results.push formatContact(fContact)

          msg.reply results.join("\n\n").trim()
