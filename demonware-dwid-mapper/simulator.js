module.exports = function(requestSimulator) {  
  var crypto = require('crypto')
  var fs = require('fs')

  var userMap = JSON.parse(fs.readFileSync('users.json'))
  var users=[]
  for (var k in userMap) { users.push(k) }
  var userCount = users.length

  requestSimulator.register(
    '/:product/:platform/users/',
    'userName_to_userID.template',    
    'GET', 
    function(data, callback) {
      if (userMap[data.userName]) {
        data.userID = userMap[data.userName]
      }
      else {
        md5sum = crypto.createHash('md5')
        md5sum.update(data.userName, 'utf8')
        var digest = md5sum.digest('hex')
        var userIndex = parseInt(digest, 16) % userCount
        data.mappedUserName = users[userIndex]
        data.userID = userMap[data.mappedUserName]
      }

      callback(data)
    }
  );
}