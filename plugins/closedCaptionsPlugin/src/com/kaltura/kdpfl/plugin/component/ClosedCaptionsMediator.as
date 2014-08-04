package com.kaltura.kdpfl.plugin.component
{
	import com.kaltura.KalturaClient;
	import com.kaltura.commands.captionAsset.CaptionAssetGetUrl;
	import com.kaltura.commands.captionAsset.CaptionAssetList;
	import com.kaltura.events.KalturaEvent;
	import com.kaltura.kdpfl.model.ConfigProxy;
	import com.kaltura.kdpfl.model.MediaProxy;
	import com.kaltura.kdpfl.model.SequenceProxy;
	import com.kaltura.kdpfl.model.ServicesProxy;
	import com.kaltura.kdpfl.model.type.NotificationType;
	import com.kaltura.types.KalturaCaptionType;
	import com.kaltura.vo.KalturaCaptionAsset;
	import com.kaltura.vo.KalturaCaptionAssetFilter;
	import com.kaltura.vo.KalturaCaptionAssetListResponse;
	import com.kaltura.vo.KalturaMediaEntry;
	import com.type.ClosedCaptionsNotifications;
	
	import flash.display.DisplayObject;
	import flash.events.AsyncErrorEvent;
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.SharedObject;
	
	import org.osmf.events.LoadEvent;
	import org.osmf.events.MediaElementEvent;
	import org.osmf.traits.LoadState;
	import org.osmf.traits.LoadTrait;
	import org.osmf.traits.MediaTraitType;
	import org.puremvc.as3.interfaces.INotification;
	import org.puremvc.as3.patterns.mediator.Mediator;

	public class ClosedCaptionsMediator extends Mediator
	{
		public static const NAME:String = "closedCaptionsMediator";
		
		private var _entryId:String = "";
		private var _flashvars:Object = null;
		private var _defaultFound : Boolean = false;
		private var _closedCaptionsDefs : closedCaptionsPluginCode;
		//new Boolean flag indicating that the entry is currently showing embedded rather than external captions.
		private var _showingEmbeddedCaptions : Boolean = false;
		private var _embeddedCaptionsId : String;
		
		private var _mediaProxy : MediaProxy;
		private var _hideClosedCaptions:Boolean  = false;
		private var _sortAlphabetically:Boolean;
		
		public function ClosedCaptionsMediator (closedCaptionsDefs:closedCaptionsPluginCode , viewComponent:Object=null , sortAlphabetically:Boolean=false)
		{
			super(NAME, viewComponent);
			_sortAlphabetically = sortAlphabetically
			_closedCaptionsDefs = closedCaptionsDefs;
		}
		
		public function get hideClosedCaptions():Boolean
		{
			return _hideClosedCaptions;
		}
		
		public function set hideClosedCaptions(value:Boolean):void
		{
			_hideClosedCaptions = value;
			(viewComponent as ClosedCaptions).visible = !_hideClosedCaptions;
		}
		
		override public function listNotificationInterests():Array
		{
			return  [
						NotificationType.MEDIA_READY,
						NotificationType.MEDIA_ELEMENT_READY,
						NotificationType.ENTRY_READY,
						NotificationType.LOAD_MEDIA,
						NotificationType.PLAYER_UPDATE_PLAYHEAD,
						NotificationType.ROOT_RESIZE,
						"closedCaptionsClicked",
						"changedClosedCaptions",
						NotificationType.LAYOUT_READY,
						ClosedCaptionsNotifications.SHOW_HIDE_CLOSED_CAPTIONS,
						ClosedCaptionsNotifications.SHOW_CLOSED_CAPTIONS,
						ClosedCaptionsNotifications.HIDE_CLOSED_CAPTIONS,
						"closedCaptionsSelected",
						"closedCaptionsSwitched",
						"newClosedCaptionsData",
						"playerPlayEnd",
						NotificationType.HAS_OPENED_FULL_SCREEN,
						NotificationType.HAS_CLOSED_FULL_SCREEN,
						ClosedCaptionsNotifications.RELOAD_CAPTIONS,
						ClosedCaptionsNotifications.LOAD_EMBEDDED_CAPTIONS
					]; 
		}
		
		override public function handleNotification(note:INotification):void
		{
			var eventName:String = note.getName();
			var data:Object = note.getBody();
			_mediaProxy = facade.retrieveProxy(MediaProxy.NAME) as MediaProxy;
			var entry:String = _mediaProxy.vo.entry.id;
			
			var sequenceProxy : SequenceProxy = facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy;
			
			//If the player is currently playing an advertisement, no need to do anything related to captions.
			if(sequenceProxy.vo.isInSequence)
			{
				return;
			}

			switch (eventName)
			{
				case NotificationType.ENTRY_READY:
				case ClosedCaptionsNotifications.RELOAD_CAPTIONS:
					(viewComponent as ClosedCaptions).resetAll();
					loadEntryCCData ();
					break;
				case NotificationType.MEDIA_ELEMENT_READY:
					addTextHandler();
					break;
				case NotificationType.MEDIA_READY:
				case "changedClosedCaptions":
				{
					
					(view as ClosedCaptions).visible= !hideClosedCaptions;
					var config: Object =  facade.retrieveProxy(ConfigProxy.NAME);
					_flashvars = config.getData().flashvars;
					
					if (_mediaProxy.vo.media != null )
					{
						_entryId = entry;
						if (_closedCaptionsDefs["type"] == null || _closedCaptionsDefs["type"] == "")
						{
							_closedCaptionsDefs["type"] = "srt";
						}

						if (_closedCaptionsDefs["ccUrl"] != null && _closedCaptionsDefs["ccUrl"] != "")
						{
							(view as ClosedCaptions).loadCaptions(_closedCaptionsDefs["ccUrl"], _closedCaptionsDefs["type"]);
						}
						
					}
				}
				break;
				
				case NotificationType.LAYOUT_READY:
					this.setStyleName(_closedCaptionsDefs.skin);
					
					if (_closedCaptionsDefs.useGlow)
					{
						setGlowFilter();
					}
					else
					{
						this.setBGColor(_closedCaptionsDefs.bg);
					}
					this.setOpacity(_closedCaptionsDefs.opacity);
					this.setFontFamily(_closedCaptionsDefs.fontFamily);
					this.setFontColor( _closedCaptionsDefs.fontColor );
					(viewComponent as ClosedCaptions).defaultFontSize = _closedCaptionsDefs.fontsize;
					if (!_closedCaptionsDefs.fullscreenRatio)
					{
						_closedCaptionsDefs.fullscreenRatio = (viewComponent as ClosedCaptions).stage.fullScreenHeight / (viewComponent as ClosedCaptions).stage.stageHeight;
					}
					(viewComponent as ClosedCaptions).fullScreenRatio = _closedCaptionsDefs.fullscreenRatio;
					(view as ClosedCaptions).addEventListener(IOErrorEvent.IO_ERROR, onCCIOError);
					(view as ClosedCaptions).addEventListener(ErrorEvent.ERROR, onCCGeneralError);
					(view as ClosedCaptions).addEventListener(AsyncErrorEvent.ASYNC_ERROR, onCCGeneralError);
					(view as ClosedCaptions).addEventListener(SecurityErrorEvent.SECURITY_ERROR, onCCGeneralError);
					(view as ClosedCaptions).addEventListener( ClosedCaptions.ERROR_PARSING_SRT, onErrorParsingCC );
					(view as ClosedCaptions).addEventListener( ClosedCaptions.ERROR_PARSING_TT, onErrorParsingCC );
					
					break;
				
				case NotificationType.PLAYER_UPDATE_PLAYHEAD:
					(view as ClosedCaptions).updatePlayhead (data as Number);
				break;
				
				case NotificationType.ROOT_RESIZE:
					setScreenSize(data.width, data.height);
				break;

				case "closedCaptionsClicked":
					(view as ClosedCaptions).closedCaptionsClicked ();
				break;
				
				case ClosedCaptionsNotifications.SHOW_HIDE_CLOSED_CAPTIONS:
					hideClosedCaptions = !hideClosedCaptions;
					break;
				case ClosedCaptionsNotifications.SHOW_CLOSED_CAPTIONS:
					hideClosedCaptions = false;
					break;
				case ClosedCaptionsNotifications.HIDE_CLOSED_CAPTIONS:
					hideClosedCaptions = true;
					break;
				case "closedCaptionsSelected":
					var currentLabel : String = note.getBody().label;
					
					if (currentLabel == _closedCaptionsDefs.noneString)
					{
						(viewComponent as ClosedCaptions).visible = false;
						saveToSO( currentLabel );
						return;
					}
					else
					{
						(viewComponent as ClosedCaptions).visible = !hideClosedCaptions;
					}
					
					for each (var ccObj : KalturaCaptionAsset in _closedCaptionsDefs.availableCCFiles)
					{
						if (currentLabel == ccObj.label)
						{
							if (ccObj.type == "tx3g")
							{
								switchEmbeddedTrack( ccObj.trackId );
							}
							else
							{
								switchActiveCCFile( ccObj );
							}
							
							saveToSO( ccObj.language );
							
							break;
						}
					
					}
					
					break;
				case "closedCaptionsSwitched":
					break;
				case "newClosedCaptionsData":		
					parseEntryCCData();
					break;
				case "playerPlayEnd":
					(viewComponent as ClosedCaptions).setText("");
					break;
				case NotificationType.HAS_OPENED_FULL_SCREEN:
					(viewComponent as ClosedCaptions).setFullScreen(true);
					break;
				case NotificationType.HAS_CLOSED_FULL_SCREEN:
					(viewComponent as ClosedCaptions).setFullScreen(false);
					break;
				case ClosedCaptionsNotifications.LOAD_EMBEDDED_CAPTIONS:
					onTextData(note.getBody());
					break;
			}
		}
		
		private function saveToSO(langKey:String):void {
			if (_flashvars.allowCookies=="true" && langKey )
			{
				try
				{
					var sharedObj : SharedObject = SharedObject.getLocal("Kaltura_CC_SO");
					sharedObj.data.language = langKey;
					sharedObj.flush();
				}
				catch (e : Error)
				{
					sendNotification( NotificationType.ALERT, {message: "Application is unable to access your file system.", title: "Error saving localized settings"} );
				}
			}
		}
		
		private function addTextHandler () : void
		{
			if (_mediaProxy.videoElement) {
				if (_mediaProxy.videoElement.client) {
					_mediaProxy.videoElement.client.addHandler( "onTextData" , onTextData );
				} else {
					var loadTrait:LoadTrait = _mediaProxy.vo.media.getTrait(MediaTraitType.LOAD) as LoadTrait;
					if ( loadTrait ) {
						loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
					}
				}
			}

		}
		
		private function onLoadStateChange(e:LoadEvent) : void {
			if (e.loadState == LoadState.READY) {
				e.target.removeEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
				if (_mediaProxy.videoElement.client) {
					_mediaProxy.videoElement.client.addHandler( "onTextData" , onTextData );
				} 
			}
		}

		private function onTextData (info : Object) : void
		{
			if (_showingEmbeddedCaptions || _closedCaptionsDefs.showEmbeddedCaptions)
				(viewComponent as ClosedCaptions).setText(info.text);
		}
		
		private function onCCIOError (e : Event) : void
		{
			sendNotification( ClosedCaptionsNotifications.CC_IO_ERROR );
		}
		
		private function onCCGeneralError (e : Event) : void
		{
			sendNotification( ClosedCaptionsNotifications.CC_ERROR );
		}
		
		private function onErrorParsingCC (e : ErrorEvent) : void
		{
			sendNotification( ClosedCaptionsNotifications.CC_FAILED_TO_VALIDATE );
		}
		
		private function onGetEntryResult(evt:Object):void
		{
			var me:KalturaMediaEntry = evt["data"] as KalturaMediaEntry;
			(view as ClosedCaptions).loadCaptions(me.downloadUrl, _flashvars.captions.type);
		}
		
		private function onGetEntryError(evt:Object):void
		{
			trace ("ClosedCaptionsPlugin: Failed to retrieve media");
		}
		
		private function loadEntryCCData () : void
		{
			var entryCCDataFilter : KalturaCaptionAssetFilter = new KalturaCaptionAssetFilter();
			
			entryCCDataFilter.entryIdEqual = (facade.retrieveProxy(MediaProxy.NAME) as MediaProxy).vo.entry.id;
			//filter only to XML and SRT (Hiding the WebVTT CC file in m3u8 that is relevant just for IOS)
			entryCCDataFilter.formatIn = KalturaCaptionType.SRT+","+KalturaCaptionType.DFXP;
			
			var entryCCDataList : CaptionAssetList = new CaptionAssetList( entryCCDataFilter );
			
			var kalturaClient : KalturaClient = (facade.retrieveProxy(ServicesProxy.NAME) as ServicesProxy).vo.kalturaClient;
			
			entryCCDataList.addEventListener( KalturaEvent.COMPLETE, captionsListSuccess );
			entryCCDataList.addEventListener( KalturaEvent.FAILED, captionsListFault );
			
			kalturaClient.post( entryCCDataList );
		}
		
		private function captionsListSuccess (e : KalturaEvent=null) : void
		{
			_closedCaptionsDefs.availableCCFiles = new Array();
			
			var listResponse : KalturaCaptionAssetListResponse = e.data as KalturaCaptionAssetListResponse;
			
			if (listResponse.objects && listResponse.objects.length) {
				for each (var ccItem : KalturaCaptionAsset in listResponse.objects )
				{
					_closedCaptionsDefs.availableCCFiles.push( ccItem );
				}
				_closedCaptionsDefs.hasCaptions = true;
				//sort			
				if(_sortAlphabetically )
					_closedCaptionsDefs.availableCCFiles.sortOn("label");
			}
			else {
				_closedCaptionsDefs.hasCaptions = false;
			}

			if ( _closedCaptionsDefs.hasCaptions )
			{
				parseEntryCCData();
				sendNotification( ClosedCaptionsNotifications.CC_DATA_LOADED );
			}
		}
		
		private function captionsListFault (e : KalturaEvent=null) : void
		{
			sendNotification( ClosedCaptionsNotifications.CC_DATA_LOAD_FAILED );
		}
		
		private function parseEntryCCData () : void
		{
			_defaultFound = false;
			_closedCaptionsDefs.availableCCFilesLabels.removeAll();
			var preferredLang : String;
			try
			{
				var sharedObj : SharedObject =  SharedObject.getLocal( "Kaltura_CC_SO" );
				preferredLang = sharedObj.data.language;
			}
			catch (e : Error)
			{
				sendNotification( NotificationType.ALERT, {message: "Application is unable to access your file system.", title: "Error saving localized settings"} );
			}
			
			var ccFileToLoad : KalturaCaptionAsset;
			for each (var ccObj : KalturaCaptionAsset in _closedCaptionsDefs.availableCCFiles)
			{
				if (!ccObj.label)
				{
					ccObj.label = ccObj.language;
				}
				
				var ccLabelObject : Object = {label: ccObj.label};
				
				_closedCaptionsDefs.availableCCFilesLabels.addItem( ccLabelObject );
				if (ccObj.isDefault >0 || _closedCaptionsDefs.defaultLanguageKey.toLowerCase() == ccObj.languageCode)
				{
					_defaultFound = true;
					ccFileToLoad = ccObj;
					
				}
				else if (!_defaultFound && ccObj.language && ccObj.language == preferredLang)
				{
					ccFileToLoad = ccObj;
				}
			}
			if (_closedCaptionsDefs.availableCCFilesLabels.length)
			{
				var selectNone : Object = {label : _closedCaptionsDefs.noneString};
				
				_closedCaptionsDefs.availableCCFilesLabels.addItemAt( selectNone , 0 );
				
				if (_closedCaptionsDefs.defaultLanguageKey==_closedCaptionsDefs.noneString || preferredLang==_closedCaptionsDefs.noneString)
				{
					_closedCaptionsDefs.currentCCFileIndex = 0;
					(viewComponent as ClosedCaptions).visible = false;
					return;
				}
			}
			
			if (ccFileToLoad)
			{
				_closedCaptionsDefs.currentCCFileIndex = findIndexByLabel( ccFileToLoad.label );
				if (ccFileToLoad.format == "tx3g")
				{
					switchEmbeddedTrack( ccFileToLoad.trackId );
				}
				else
				{ 
					switchActiveCCFile ( ccFileToLoad )
				}
			}
		}
		
		private function findIndexByLabel (ccLabel : String) : int
		{
			for (var i:int=0; i < _closedCaptionsDefs.availableCCFilesLabels.toArray().length; i++)
			{
				if (ccLabel == _closedCaptionsDefs.availableCCFilesLabels.toArray()[i].label)
				{
					return i;
				}
			}
			return -1;
		}
		
		private function switchEmbeddedTrack  (id: String) : void
		{
			(viewComponent as ClosedCaptions).currentCCFile = new Array();
			(viewComponent as ClosedCaptions).setText("");
			_embeddedCaptionsId = id;
			_showingEmbeddedCaptions = true;
			
		}
		
		private function switchActiveCCFile ( ccFileAsset : KalturaCaptionAsset) : void
		{
			_showingEmbeddedCaptions = false;
			
			var kalturaClient : KalturaClient = (facade.retrieveProxy(ServicesProxy.NAME) as ServicesProxy).vo.kalturaClient;
			
			var getCaptionsUrl : CaptionAssetGetUrl = new CaptionAssetGetUrl ( ccFileAsset.id );
			
			getCaptionsUrl.addEventListener( KalturaEvent.COMPLETE, loadActiveCCFile );
			
			getCaptionsUrl.addEventListener( KalturaEvent.FAILED, getURLFailed );
			
			kalturaClient.post(getCaptionsUrl);
			
			function loadActiveCCFile ( e : KalturaEvent) : void
			{
				(viewComponent as ClosedCaptions).loadCaptions(e.data as String, ccFileAsset.format);
			}
			
			function getURLFailed ( e : KalturaEvent) : void
			{
				
			}
		}
		
		
		
		public function get view() : DisplayObject
		{
			return viewComponent as DisplayObject;
		}

		public function setScreenSize( w:Number, h:Number) : void  
		{
			// Call when video player window changes size (example fullscreen)
			(view as ClosedCaptions).setDimensions(w,h);
		}
		
		public function setBGColor (val : Number) : void
		{
			(view as ClosedCaptions).defaultBGColor = val;
		}		
		public function setStyleName ( val : String ) : void
		{
			(view as ClosedCaptions).setSkin(val); 
		}
		
		public function setOpacity ( val : String ) : void
		{
			(view as ClosedCaptions).bgAlpha = val;
		}
		
		public function setFontFamily (val : String) : void
		{
			(view as ClosedCaptions).defaultFontFamily = val;
		}
		
		public function setFontColor (val : Number) : void
		{
			(view as ClosedCaptions).defaultFontColor = val;
		}
		
		public function setGlowFilter () : void
		{
			(viewComponent as ClosedCaptions).setBitmapFilter( _closedCaptionsDefs.glowColor, _closedCaptionsDefs.glowBlur );
		}

	}
}