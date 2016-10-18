//
//  HorizontalTableView.swift
//  TGUIKit
//
//  Created by keepcoder on 17/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa

public class HorizontalTableView: TableView {

    public override init(frame frameRect: NSRect, isFlipped: Bool = true) {
        super.init(frame: frameRect, isFlipped: isFlipped)
        //        [[self.scrollView verticalScroller] setControlSize:NSSmallControlSize];
        self.verticalScroller?.controlSize = NSControlSize.small
        self.rotate(byDegrees: 270)
        
        self.clipView.border = []
        self.tableView.border = []
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func rowView(item:TableRowItem) -> TableRowView {
        var identifier:String = NSStringFromClass(item.viewClass())
        var view = self.tableView.make(withIdentifier: identifier, owner: self.tableView)
        if(view == nil) {
            var vz = item.viewClass() as! TableRowView.Type
            
            view = vz.init(frame:NSMakeRect(0, 0, item.height, frame.height))
            
            view?.identifier = identifier
            
        }
        
        return view as! TableRowView;
    }
    
}