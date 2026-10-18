import AppKit

enum CasaBrand {
    static var menuIcon: NSImage {
        let image = NSImage(size:NSSize(width:20,height:20),flipped:false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let house = NSBezierPath(); house.lineWidth = 1.65; house.lineCapStyle = .round; house.lineJoinStyle = .round
            house.move(to:NSPoint(x:2,y:10)); house.line(to:NSPoint(x:10,y:17)); house.line(to:NSPoint(x:18,y:10))
            house.move(to:NSPoint(x:4,y:10)); house.line(to:NSPoint(x:4,y:3)); house.line(to:NSPoint(x:16,y:3)); house.line(to:NSPoint(x:16,y:10)); house.stroke()
            let links = NSBezierPath(); links.lineWidth = 1.2
            links.move(to:NSPoint(x:7,y:6)); links.line(to:NSPoint(x:10,y:11)); links.line(to:NSPoint(x:13,y:6)); links.stroke()
            for (x,y) in [(7.0,6.0),(10.0,11.0),(13.0,6.0)] { NSBezierPath(ovalIn:NSRect(x:x-1.4,y:y-1.4,width:2.8,height:2.8)).fill() }
            return true
        }
        image.isTemplate = true
        return image
    }
}
