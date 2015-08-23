using afIoc
using afBedSheet
using afBedSheet::Text as BsText
using afConcurrent::Synchronized
using afDuvet::DuvetModule
using afDuvet::HtmlInjector
using concurrent::ActorPool
using fwt
using web::WebReq
using web::WebRes
using concurrent

internal class Chatbox {	
	Void main(Str[] args) {
		if (args.first == "-client")
			ChatboxClient().main
		else
			BedSheetBuilder(AppModule#.qname).startWisp(8069)
	}
}

internal class AppModule {
	@Contribute { serviceType=Routes# }
	static Void contributeRoutes(Configuration conf) {
		conf.add(Route(`/`, 	ChatboxRoutes#indexPage))
		conf.add(Route(`/ws`,	ChatboxRoutes#serviceWebSocket))
	}
}

internal const class ChatboxRoutes {
	@Inject private const WebSockets	webSockets
	@Inject private const HtmlInjector	htmlInjector
	
	new make(|This|in) { in(this) }

	BsText indexPage() {
		htmlInjector.injectFantomMethod(ChatboxClient#main)
		return BsText.fromHtml(
			"<!DOCTYPE html>
			 <html>
			 <head>
			 	<title>ChatBox - A WebSocket Demo</title>
			 </head>
			 <body>
			 </body>
			 </html>")
	}
	
	WebSocket serviceWebSocket() {
		echo("serviceWebSocket")
		ws := WebSocket.make() {
			ws := it
			onMessage = |MsgEvent me| { 
				webSockets.broadcast("${ws.id} says, '${me.txt}'")
			}
		}.upgrade(webReq, webRes)
//		bigTxt := Buf.random(160000).toBase64
		bigTxt := Buf.random(1600).toBase64
		echo("sending $bigTxt.size bytes")
		ws.sendText(bigTxt)
		return ws
	}
	
	private WebReq webReq() {
		Actor.locals["web.req"] ?: throw Err("No web request active in thread")
	}

	private WebRes webRes() {
		Actor.locals["web.res"] ?: throw Err("No web request active in thread")
	}
}

@Js
internal class ChatboxClient {
	Void main() {
		webSock := WebSocket.make().open(`ws://localhost:8069/ws`)
		convBox := Text { text = "The conversation:\r\n"; multiLine = true; editable = false }
		textBox := Text { text = "Say somethingz!" }
		sendMsg := |Event e| {
			webSock.sendText(textBox.text)
			textBox.text = ""
		}

		webSock.onMessage = |MsgEvent msgEnv| {
			convBox.text += "\r\n" + msgEnv.txt			
		}

		webSock.onClose = |CloseEvent ce| {
			convBox.text += "\r\nClosed: $ce"			
		}

		webSock.onError = |Err err| {
			convBox.text += "\r\nErr: $err"			
		}

		textBox.onAction.add(sendMsg)

		window := Window {
			title = "ChatBox - A WebSocket Demo"
			InsetPane {
				EdgePane {
					center	= convBox
					bottom	= EdgePane {
						center	= textBox
						right	= Button { text = "Send"; onAction.add(sendMsg) }
					}
				},
			},
        }
		
		// desktop only code
		if (Env.cur.runtime != "js") {
			// ensure event funcs are run in the UI thread
			safeFunc := Unsafe(webSock.onMessage)
			webSock.onMessage = |MsgEvent msgEnv| {
				echo("got msg")
				safeMess := Unsafe(msgEnv)
				Desktop.callAsync |->| { safeFunc.val->call(safeMess.val) }
			}

			// call the blocking read() method in a background thread
			safeSock := Unsafe(webSock)
			Synchronized(ActorPool()).async |->| {
				try
					safeSock.val->read
				catch (Err err) err.trace
			}
		}

		window.open
	}
}
