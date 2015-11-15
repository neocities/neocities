var page   = require('webpage').create()
var system = require('system')

var maxTimeout = 15000

if (system.args.length === 1) {
  console.log('required args: <siteURL> <outputFilePath>');
  phantom.exit(1)
}

var address = system.args[1]
var outputPath = system.args[2]

page.viewportSize = { width: 1280, height: 960 }
page.clipRect = { top: 0, left: 0, width: 1280, height: 960}

/*
In development, not working yet.

page.settings.scriptTimeout = 1000

page.onLongRunningScript = function() {
  page.stopJavaScript()
  phantom.exit(4)
}
*/

var t = Date.now()

console.log('Loading ' + address)

setTimeout(function() {
  console.log('timeout')
  phantom.exit(62)
}, maxTimeout)

page.settings.resourceTimeout = maxTimeout

page.onResourceTimeout = function(e) {
  console.log(e.errorCode)
  console.log(e.errorString)
  console.log(e.url)
  phantom.exit(3)
}

page.open(address, function(status) {
  if(status !== 'success') {
    console.log('failed')
    phantom.exit(2)
  }

  page.render(outputPath)
  console.log('Loading time ' + (Date.now() - t) + ' msec');
  phantom.exit()
})

