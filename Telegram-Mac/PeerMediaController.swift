 //
//  PeerMediaController.swift
//  Telegram-Mac
//
//  Created by keepcoder on 13/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCoreMac
import SwiftSignalKitMac
import PostboxMac


class PeerMediaControllerView : View {
    
    private let actionsPanelView:MessageActionsPanelView = MessageActionsPanelView(frame: NSMakeRect(0,0,0, 50))
    fileprivate let typesContainerView: View = View()
    fileprivate let segmentControl = SegmentController(frame: NSMakeRect(0, 0, 200, 28))
    private weak var mainView:NSView?
    private let separator:View = View()
    private var isSelectionState:Bool = false
    private var chatInteraction:ChatInteraction?
    required init(frame frameRect:NSRect) {
        super.init(frame: frameRect)
        addSubview(actionsPanelView)
        addSubview(separator)
        typesContainerView.addSubview(segmentControl.view)
        addSubview(typesContainerView)
        updateLocalizationAndTheme()
    }
    
    override func updateLocalizationAndTheme() {
        super.updateLocalizationAndTheme()
        separator.backgroundColor = theme.colors.border
        mainView?.background = theme.colors.background
    }
    
    func updateInteraction(_ chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
        actionsPanelView.prepare(with: chatInteraction)
    }
    
    
    func updateMainView(with view:NSView, animated:Bool) {
        mainView?.removeFromSuperview()
        mainView?.background = theme.colors.background
        self.mainView = view
        addSubview(view, positioned: .below, relativeTo: actionsPanelView)
        needsLayout = true
    }
    

    
    func changeState(selectState:Bool, animated:Bool) {
        assert(mainView != nil)
        
        self.isSelectionState = selectState
        let inset:CGFloat = selectState ? 50 : 0

      //  mainView?.setFrameSize(NSMakeSize(frame.width, frame.height - inset))
        
        actionsPanelView.change(pos: NSMakePoint(0, frame.height - inset), animated: animated)
        separator.change(pos: NSMakePoint(0, frame.height - inset), animated: animated)
    }
    
    override func layout() {
        
        let inset:CGFloat = isSelectionState ? 50 : 0
        typesContainerView.frame = NSMakeRect(0, 0, frame.width, 50)
        segmentControl.view.setFrameSize(frame.width - 20, 28)
        segmentControl.view.center()
        mainView?.frame = NSMakeRect(0, typesContainerView.frame.maxY, frame.width, frame.height - inset - typesContainerView.frame.maxY)
        actionsPanelView.frame = NSMakeRect(0, frame.height - inset, frame.width, 50)
        separator.frame = NSMakeRect(0, frame.height - inset, frame.width, .borderSize)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PeerMediaController: EditableViewController<PeerMediaControllerView>, Notifable {

    private let peerId:PeerId
    private var peer:Peer?
    
    private var tagMask:MessageTags
    private var mode:PeerMediaCollectionMode = .photoOrVideo
    
    private let mediaGrid:PeerMediaGridController
    private let listControllers:[PeerMediaListController]
    private let tagsList:[PeerMediaCollectionMode] = [.file, .webpage, .music, .voice]
    private var currentTagListIndex: Int = -1
    private var interactions:ChatInteraction
    private let messagesActionDisposable:MetaDisposable = MetaDisposable()
    private let loadFwdMessagesDisposable = MetaDisposable()
    private let loadSelectionMessagesDisposable = MetaDisposable()
    private let currentModeValue:ValuePromise<PeerMediaCollectionMode> = ValuePromise(.photoOrVideo, ignoreRepeated: true)
    init(account:Account, peerId:PeerId, tagMask:MessageTags) {
        self.peerId = peerId
        self.tagMask = tagMask
        
        interactions = ChatInteraction(chatLocation: .peer(peerId), account: account)
        
        
        mediaGrid = PeerMediaGridController(account: account, chatLocation: .peer(peerId), messageId: nil, tagMask: tagMask, chatInteraction: interactions)
        
        var listControllers: [PeerMediaListController] = []
        for _ in tagsList {
            listControllers.append(PeerMediaListController(account: account, chatLocation: .peer(peerId), chatInteraction: interactions))
        }
        self.listControllers = listControllers
        
        
        super.init(account)
    }
    
    private var temporaryTouchBar: Any?
    
    @available(OSX 10.12.2, *)
    override func makeTouchBar() -> NSTouchBar? {
        if temporaryTouchBar == nil {
            temporaryTouchBar = PeerMediaTouchBar(chatInteraction: interactions, currentMode: currentModeValue.get(), toggleMode: { [weak self] value in
                self?.toggle(with: value, animated: false)
                self?.genericView.segmentControl.set(selected: value.rawValue)
            })
        }
        return temporaryTouchBar as? NSTouchBar
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        interactions.add(observer: self)
        if self.mode == .photoOrVideo {
            self.mediaGrid.viewDidAppear(animated)
        } else {
            self.listControllers[currentTagListIndex].viewDidAppear(animated)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        interactions.remove(observer: self)
        if self.mode == .photoOrVideo {
            self.mediaGrid.viewDidDisappear(animated)
        } else {
            self.listControllers[currentTagListIndex].viewDidDisappear(animated)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.mode == .photoOrVideo {
            self.mediaGrid.viewWillAppear(animated)
        } else {
            self.listControllers[currentTagListIndex].viewWillAppear(animated)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.mode == .photoOrVideo {
            self.mediaGrid.viewWillDisappear(animated)
        } else {
            self.listControllers[currentTagListIndex].viewWillDisappear(animated)
        }
    }
    
    func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            
            let account = self.account
            if value.selectionState != oldValue.selectionState {
                if let selectionState = value.selectionState {
                    let ids = Array(selectionState.selectedIds)
                    loadSelectionMessagesDisposable.set((account.postbox.messagesAtIds(ids) |> deliverOnMainQueue).start( next:{ [weak self] messages in
                        var canDelete:Bool = !ids.isEmpty
                        var canForward:Bool = !ids.isEmpty
                        for message in messages {
                            if !canDeleteMessage(message, account: account) {
                                canDelete = false
                            }
                            if !canForwardMessage(message, account: account) {
                                canForward = false
                            }
                        }
                        self?.interactions.update({$0.withUpdatedBasicActions((canDelete, canForward))})
                    }))
                } else {
                    interactions.update({$0.withUpdatedBasicActions((false, false))})
                }
            }
            
            if (value.state == .selecting) != (oldValue.state == .selecting) {
                self.state = value.state == .selecting ? .Edit : .Normal
                genericView.changeState(selectState: value.state == .selecting, animated: animated)
                
                if mode == .photoOrVideo {
                    self.mediaGrid.genericView.grid.forEachItemNode { itemNode in
                        if let itemNode = itemNode as? GridMessageItemNode {
                            itemNode.updateSelectionState(animated: animated)
                        }
                    }
                }
               
            }
            
        }
    }

    
    func isEqual(to other: Notifable) -> Bool {
        if let other = other as? PeerMediaController {
            return self == other
        }
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        genericView.updateInteraction(interactions)
        
        
        interactions.forwardMessages = { [weak self] messageIds in
            if let strongSelf = self {
                showModal(with: ShareModalController.init(ForwardMessagesObject(strongSelf.account, messageIds: messageIds)), for: mainWindow)
//                strongSelf.loadFwdMessagesDisposable.set((strongSelf.account.postbox.messagesAtIds(messageIds) |> deliverOnMainQueue).start(next: { [weak strongSelf] messages in
//                    if let strongSelf = strongSelf {
//
//                        let displayName:String = strongSelf.peer?.compactDisplayTitle ?? "Unknown"
//                        let action = FWDNavigationAction(messages: messages, displayName: displayName)
//                        navigation.set(modalAction: action, strongSelf.account.context.layout != .single)
//
//                        if strongSelf.account.context.layout == .single {
//                            navigation.push(ForwardChatListController(strongSelf.account))
//                        }
//
//                        action.afterInvoke = { [weak strongSelf] in
//                            strongSelf?.interactions.update(animated: false, {$0.withoutSelectionState()})
//                            strongSelf?.interactions.saveState()
//                        }
//
//                    }
//                }))
            }
        }
        
        interactions.focusMessageId = { [weak self] _, focusMessageId, animated in
            if let strongSelf = self {
                strongSelf.navigationController?.push(ChatController(account: strongSelf.account, chatLocation: .peer(strongSelf.peerId), messageId: focusMessageId))
            }
        }
        
        interactions.inlineAudioPlayer = { [weak self] controller in
            if let navigation = self?.navigationController, let `self` = self {
                if let header = navigation.header {
                    header.show(true)
                    if let view = header.view as? InlineAudioPlayerView {
                        let tableView = (navigation.first { $0 is ChatController} as? ChatController)?.genericView.tableView
                        view.update(with: controller, tableView: tableView, supportTableView: self.currentTable)
                    }
                }
            }
        }
        
        interactions.openInfo = { [weak self] (peerId, toChat, postId, action) in
            if let strongSelf = self {
                if toChat {
                    strongSelf.navigationController?.push(ChatController(account: strongSelf.account, chatLocation: .peer(peerId), messageId: postId, initialAction: action))
                } else {
                    strongSelf.navigationController?.push(PeerInfoController(account: strongSelf.account, peerId: peerId))
                }
            }
        }
        
        interactions.deleteMessages = { [weak self] messageIds in
            if let strongSelf = self, let peer = strongSelf.peer {
                let channelAdmin:Signal<[ChannelParticipant]?, NoError> = peer.isSupergroup ? channelAdmins(account: strongSelf.account, peerId: strongSelf.interactions.peerId)
                    |> `catch` {_ in .complete()} |> map { admins -> [ChannelParticipant]? in
                        return admins.map({$0.participant})
                    } : .single(nil)
                
                
                self?.messagesActionDisposable.set(combineLatest(strongSelf.account.postbox.messagesAtIds(messageIds) |> deliverOnMainQueue, channelAdmin |> deliverOnMainQueue).start( next:{ [weak strongSelf] messages, admins in
                    if let strongSelf = strongSelf {
                        var canDelete:Bool = true
                        var canDeleteForEveryone = true
                        
                        for message in messages {
                            if !canDeleteMessage(message, account: strongSelf.account) {
                                canDelete = false
                            }
                            if !canDeleteForEveryoneMessage(message, account: strongSelf.account) {
                                canDeleteForEveryone = false
                            }
                        }
                        if messages.isEmpty {
                            strongSelf.interactions.update({$0.withoutSelectionState()})
                            return
                        }
                        
                        if canDelete {
                            let isAdmin = admins?.filter({$0.peerId == messages[0].author?.id}).first != nil
                            if mustManageDeleteMessages(messages, for: peer, account: strongSelf.account), let memberId = messages[0].author?.id, !isAdmin {
                                showModal(with: DeleteSupergroupMessagesModalController(account: strongSelf.account, messageIds: messages.map {$0.id}, peerId: peer.id, memberId: memberId, onComplete: { [weak strongSelf] in
                                    strongSelf?.interactions.update({$0.withoutSelectionState()})
                                }), for: mainWindow)
                            } else {
                                let thrid:String? = canDeleteForEveryone ? peer.isUser ? tr(L10n.chatMessageDeleteForMeAndPerson(peer.compactDisplayTitle)) : tr(L10n.chatConfirmDeleteMessagesForEveryone) : nil
                                var okTitle: String? = tr(L10n.confirmDelete)
                                if peer.isUser || peer.isGroup {
                                    okTitle = peer.id == strongSelf.account.peerId ? tr(L10n.confirmDelete) : tr(L10n.chatMessageDeleteForMe)
                                } else {
                                    okTitle = tr(L10n.chatMessageDeleteForEveryone)
                                }
                                if let window = self?.window {
                                    confirm(for: window, header: tr(L10n.chatConfirmActionUndonable), information: tr(L10n.chatConfirmDeleteMessages), okTitle: okTitle, thridTitle:thrid, successHandler: { result in
                                        let type:InteractiveMessagesDeletionType
                                        switch result {
                                        case .basic:
                                            type = .forLocalPeer
                                        case .thrid:
                                            type = .forEveryone
                                        }
                                        _ = deleteMessagesInteractively(postbox: strongSelf.account.postbox, messageIds: messageIds, type: type).start()
                                        strongSelf.interactions.update({$0.withoutSelectionState()})
                                    })
                                }
                            }
                        }
                    }
                }))
            }
        }
        
        let peerSignal = account.viewTracker.peerView(peerId) |> deliverOnMainQueue |> beforeNext({ [weak self] peerView in
            self?.peer = peerView.peers[peerView.peerId]
        }) |> map { view -> Bool in
            return true
        }
        
        let combined = combineLatest( [peerSignal |> take(1), mediaGrid.ready.get()] ) |> map { result -> Bool in
            return result[0] && result[1]
        }
        
        self.ready.set(combined |> deliverOnMainQueue)
    }
    
    private var currentTable: TableView? {
        if self.mode == .photoOrVideo {
            return nil
        } else {
            return self.listControllers[currentTagListIndex].genericView
        }
    }
    override func loadView() {
        super.loadView()
 
        for i in 0 ..< listControllers.count {
            listControllers[i].loadViewIfNeeded(bounds)
            listControllers[i].load(with: tagsList[i].tagsValue)
        }
        mediaGrid.loadViewIfNeeded(bounds)
        
        mediaGrid.viewWillAppear(false)
        genericView.updateMainView(with: mediaGrid.view, animated: false)
        mediaGrid.viewDidAppear(false)
        
        requestUpdateCenterBar()
        updateLocalizationAndTheme()
    }
    
    private func toggle(with mode:PeerMediaCollectionMode, animated:Bool = false) {
        currentModeValue.set(mode)
        if self.mode != mode {
            self.mode = mode
            if mode == .photoOrVideo {
                mediaGrid.viewWillAppear(animated)
                self.listControllers[currentTagListIndex].viewWillDisappear(animated)
                mediaGrid.view.frame = bounds
                genericView.updateMainView(with: mediaGrid.view, animated: animated)
                mediaGrid.viewDidAppear(animated)
                self.listControllers[currentTagListIndex].removeFromSuperview()
                self.listControllers[currentTagListIndex].viewDidDisappear(animated)
                currentTagListIndex = -1

            } else {
                let previous: ViewController
                if currentTagListIndex != -1 {
                    previous = self.listControllers[currentTagListIndex]
                } else {
                    previous = mediaGrid
                }
                self.currentTagListIndex = tagsList.firstIndex(of: mode)!
                self.listControllers[currentTagListIndex].viewWillAppear(animated)
                previous.viewWillDisappear(animated)
                self.listControllers[currentTagListIndex].view.frame = bounds
                genericView.updateMainView(with: self.listControllers[currentTagListIndex].view, animated: animated)
                self.listControllers[currentTagListIndex].viewDidAppear(animated)
                previous.removeFromSuperview()
                previous.viewDidDisappear(animated)
            }
            
        }
        
    }
    
    
    deinit {
        messagesActionDisposable.dispose()
        loadFwdMessagesDisposable.dispose()
        loadSelectionMessagesDisposable.dispose()
    }
    
    override func updateLocalizationAndTheme() {
        super.updateLocalizationAndTheme()
        genericView.segmentControl.removeAll()
        
        genericView.segmentControl.add(segment: SegmentedItem(title: L10n.peerMediaMedia, handler: { [weak self] in
            self?.toggle(with: .photoOrVideo, animated:true)
        }))
        
        genericView.segmentControl.add(segment: SegmentedItem(title: L10n.peerMediaFiles, handler: { [weak self] in
            self?.toggle(with: .file, animated:true)
        }))
        
        genericView.segmentControl.add(segment: SegmentedItem(title: L10n.peerMediaLinks, handler: { [weak self] in
            self?.toggle(with: .webpage, animated:true)
        }))
        
        genericView.segmentControl.add(segment: SegmentedItem(title: L10n.peerMediaAudio, handler: { [weak self] in
            self?.toggle(with: .music, animated:true)
        }))
        
        genericView.segmentControl.add(segment: SegmentedItem(title: L10n.peerMediaVoice, handler: { [weak self] in
            self?.toggle(with: .voice, animated:true)
        }))
    }
    
    override public func update(with state:ViewControllerState) -> Void {
        super.update(with:state)
        interactions.update({state == .Normal ? $0.withoutSelectionState() : $0.withSelectionState()})
    }
  
    override func navigationHeaderDidNoticeAnimation(_ current: CGFloat, _ previous: CGFloat, _ animated: Bool) -> () -> Void {
        for mediaList in listControllers {
            if mediaList.view.superview != nil {
                if current == 0 {
                    genericView.typesContainerView.setFrameOrigin(genericView.typesContainerView.frame.minX, 50)
                }
                genericView.typesContainerView._change(pos: NSMakePoint(genericView.typesContainerView.frame.minX, current), animated: animated)
                return mediaList.navigationHeaderDidNoticeAnimation(current, previous, animated)
            }
        }
       
        if mediaGrid.view.superview != nil {
            return mediaGrid.navigationHeaderDidNoticeAnimation(current, previous, animated)
        }
        return {}
    }
    
}



