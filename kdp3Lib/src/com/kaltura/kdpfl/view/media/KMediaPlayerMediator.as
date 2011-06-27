package com.kaltura.kdpfl.view.media
{
	import com.kaltura.kdpfl.controller.media.LiveStreamCommand;
	import com.kaltura.kdpfl.model.ConfigProxy;
	import com.kaltura.kdpfl.model.ExternalInterfaceProxy;
	import com.kaltura.kdpfl.model.MediaProxy;
	import com.kaltura.kdpfl.model.PlayerStatusProxy;
	import com.kaltura.kdpfl.model.SequenceProxy;
	import com.kaltura.kdpfl.model.strings.MessageStrings;
	import com.kaltura.kdpfl.model.type.NotificationType;
	import com.kaltura.kdpfl.model.type.SourceType;
	import com.kaltura.kdpfl.model.type.StreamerType;
	import com.kaltura.kdpfl.view.controls.BufferAnimation;
	import com.kaltura.kdpfl.view.controls.BufferAnimationMediator;
	import com.kaltura.types.KalturaMediaType;
	import com.kaltura.vo.KalturaLiveStreamEntry;
	import com.kaltura.vo.KalturaMediaEntry;
	import com.kaltura.vo.KalturaMixEntry;
	
	import fl.events.ComponentEvent;
	
	import flash.display.DisplayObjectContainer;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.utils.setTimeout;
	
	import org.osmf.events.AudioEvent;
	import org.osmf.events.BufferEvent;
	import org.osmf.events.DisplayObjectEvent;
	import org.osmf.events.DynamicStreamEvent;
	import org.osmf.events.LoadEvent;
	import org.osmf.events.MediaElementEvent;
	import org.osmf.events.MediaErrorEvent;
	import org.osmf.events.MediaPlayerCapabilityChangeEvent;
	import org.osmf.events.MediaPlayerStateChangeEvent;
	import org.osmf.events.TimeEvent;
	import org.osmf.media.MediaPlayer;
	import org.osmf.media.MediaPlayerState;
	import org.osmf.traits.DynamicStreamTrait;
	import org.osmf.traits.MediaTraitBase;
	import org.osmf.traits.MediaTraitType;
	import org.osmf.traits.TimeTrait;
	import org.puremvc.as3.interfaces.INotification;
	import org.puremvc.as3.patterns.mediator.Mediator;
	
	/**
	 * Mediator for the KMediaPlayer component 
	 * 
	 */	
	public class KMediaPlayerMediator extends Mediator
	{
		public static const NAME:String = "kMediaPlayerMediator";
		public var isInSequence : Boolean = false;
		
		private var _bytesLoaded:Number;//keeps loaded bytes for intelligent seeking
		private var _bytesTotal:Number;//keeps total bytes for intelligent seeking
		private var _duration:Number;//keeps duration for intelligent seeking
		private var _blockThumb : Boolean = false;
		private var _mediaProxy : MediaProxy; 
        private var _offset:Number=0
        private var _loadedTime:Number;
        private var _flashvars:Object;
        private var _url:String;
        private var _seekUrl:String;
        private var _autoMute:Boolean=false;
        private var _isIntelliSeeking :Boolean=false;
        private var _intelliSeekStart:Number=0;
        private var _currentTime:Number;
        private var _lastCurrentTime:Number = 0;
        private var _newdDuration:Number;
        //private var _actuallyPlays:Boolean=false;
        private var _kdp3Preloader : BufferAnimation;
        private var _autoPlay : Boolean;
        private var _hasPlayed : Boolean = false;
        private var _playerReadyOrEmptyFlag : Boolean = false;
        private var _alertCalled: Boolean = false;
		private var _flvChunkDuration : Number;
        public var playBeforeMixReady : Boolean = true;
        private var _mixLoaded : Boolean = false;
		private var _prevState : String;
        /**
         * This flag fix OSMF issue that on playend you get somtimes MediaPlayerReady
         * so to fix this I added this flag 
         */        
        private var _loadMediaOnPlay : Boolean = false;
        
        
		/**
		 * Constructor 
		 * @param name
		 * @param viewComponent
		 * 
		 */		
		public function KMediaPlayerMediator(name:String=null, viewComponent:Object=null)
		{
			name = name ? name : NAME;
			super(name, viewComponent);
			
			var configProxy : ConfigProxy = facade.retrieveProxy( ConfigProxy.NAME ) as ConfigProxy;
			_flashvars = configProxy.vo.flashvars;
			kMediaPlayer.isFileSystemMode = _flashvars.fileSystemMode;
		}
		
		/**
		 * Hadnler for the mediator registration; defines the _mediaProxy and _flashvars for the mediator.
		 * Also sets the bg color of the player, adds the event listeners for the events fired from the OSMF to be translated into notifications.
		 * and will listen to all the required events 
		 * 
		 */		
		override public function onRegister():void
		{	
			_mediaProxy = facade.retrieveProxy( MediaProxy.NAME ) as MediaProxy;
			var configProxy : ConfigProxy = facade.retrieveProxy( ConfigProxy.NAME ) as ConfigProxy;
			_flashvars = configProxy.vo.flashvars;
			
			//if we got a player bj color from flashvars we will color the back screen
			if(_flashvars.playerBgColor != null)
			{
				var bgColor : uint = uint(_flashvars.playerBgColor);
				var alpha : Number = _flashvars.playerBgAlpha ? _flashvars.playerBgAlpha : 1;
				kMediaPlayer.drawBg( bgColor , alpha );
			}
			
			//set autoPlay,loop,and autoRewind from flashvars
			
			//autoPlay Indicates whether the MediaPlayer starts playing the media as soon as its load operation has successfully completed.
			if(_flashvars.autoPlay == "true") _autoPlay = true;
				
			//loop Indicates whether the media should play again after playback has completed
			if(_flashvars.loop == "true") player.loop =  true;
			
			//autoRewind Indicates which frame of a video the MediaPlayer displays after playback completes. 
			if(_flashvars.autoRewind == "true") player.autoRewind =  true;
			
			//if an autoMute flashvar passed as true mute the volume 
			if(_flashvars.autoMute == "true") _autoMute=true;
	
			//add all the event listeners needed from video component to make the KDP works
			player.addEventListener( DisplayObjectEvent.DISPLAY_OBJECT_CHANGE , onViewableChange );
			player.addEventListener( DisplayObjectEvent.MEDIA_SIZE_CHANGE , onMediaSizeChange );		
			
			player.addEventListener( MediaPlayerStateChangeEvent.MEDIA_PLAYER_STATE_CHANGE , onPlayerStateChange );
				
			player.addEventListener( TimeEvent.CURRENT_TIME_CHANGE , onPlayHeadChange );
			player.addEventListener( AudioEvent.VOLUME_CHANGE , onVolumeChangeEvent );
			player.addEventListener( BufferEvent.BUFFER_TIME_CHANGE , onBufferTimeChange );
			player.addEventListener( BufferEvent.BUFFERING_CHANGE , onBufferingChange );
			player.addEventListener( MediaErrorEvent.MEDIA_ERROR , onMediaError );
			
			player.addEventListener( LoadEvent.BYTES_TOTAL_CHANGE , onBytesTotalChange );
			player.addEventListener( LoadEvent.BYTES_LOADED_CHANGE , onBytesDownloadedChange );
			player.addEventListener( TimeEvent.DURATION_CHANGE , onDurationChange );
			
			player.addEventListener( DynamicStreamEvent.SWITCHING_CHANGE , onSwitchingChange );
			
			
			if(_flashvars.disableOnScreenClick)
			{
				disableOnScreenClick();
			}
		}
				
		public function centerMediator () : void 
		{
			var size : Object = {width : playerContainer.width, height : playerContainer.height};
			
			_kdp3Preloader.height = size.height;
			_kdp3Preloader.width = size.width;
		}
		
		
		/**
		 * Enables play/pause on clicking the video.
		 * 
		 */		
		public function enableOnScreenClick() : void
		{
			if(kMediaPlayer && !kMediaPlayer.hasEventListener(MouseEvent.CLICK))
				kMediaPlayer.addEventListener( MouseEvent.CLICK , onMClick );
		}
		/**
		 * Disables play/pause on clicking the screen. 
		 * 
		 */		
		public function disableOnScreenClick() : void
		{
			if(kMediaPlayer && kMediaPlayer.hasEventListener(MouseEvent.CLICK))
				kMediaPlayer.removeEventListener( MouseEvent.CLICK , onMClick );
		}
		/**
		 * Hnadler for on-screen click 
		 * @param event
		 * 
		 */		
		private function onMClick( event : MouseEvent ) : void 
		{
			if( player.canPlay && !player.playing )
				sendNotification(NotificationType.DO_PLAY);
			else if( player.canPause && player.playing) 
				sendNotification(NotificationType.DO_PAUSE);
		}
	    
		/**
		 * List of the notifications that interest the player
		 * @return 
		 * 
		 */	    
		override public function listNotificationInterests():Array
		{
			return [
					NotificationType.SOURCE_READY,
					NotificationType.DO_PLAY,
					NotificationType.ENTRY_READY,
					NotificationType.DO_STOP,
					NotificationType.CHANGE_MEDIA_PROCESS_STARTED,
					NotificationType.DO_PAUSE,
					NotificationType.DO_SEEK,
					NotificationType.DO_SWITCH,
					NotificationType.CLEAN_MEDIA,
					NotificationType.CHANGE_VOLUME,
					NotificationType.MEDIA_READY,
					NotificationType.MEDIA_LOAD_ERROR,
					NotificationType.KDP_EMPTY,
				    NotificationType.KDP_READY,
				    LiveStreamCommand.LIVE_STREAM_READY,
					NotificationType.LIVE_ENTRY,
					NotificationType.PLAYER_SEEK_START,
					NotificationType.ENTRY_READY,
					NotificationType.PLAYER_PLAYED
				   ];
		}
		
		/**
		 * Notification handler of the KMediaPlayerMediator
		 * @param note
		 * 
		 */		
		override public function handleNotification(note:INotification):void
		{
			var sequenceProxy : SequenceProxy = facade.retrieveProxy( SequenceProxy.NAME ) as SequenceProxy; 
			switch(note.getName())
			{
				case NotificationType.ENTRY_READY:
					
					if(_mediaProxy.vo)
					{
						if( !sequenceProxy.vo.isInSequence)
							kMediaPlayer.loadThumbnail( _mediaProxy.vo.entry.thumbnailUrl,_mediaProxy.vo.entry.width,_mediaProxy.vo.entry.height ); //load the thumnail of this media
					}
					if (_flashvars.autoPlay !="true" && !_mediaProxy.vo.singleAutoPlay)
					{
						kMediaPlayer.showThumbnail();
					}
					else
					{
						kMediaPlayer.hideThumbnail();
					}
					break;
				case NotificationType.SOURCE_READY: //when the source is ready for the media element
	
					cleanMedia(); //clean the media element if exist
					
					setSource(); //set the source to the player

				break;
				case NotificationType.CHANGE_MEDIA_PROCESS_STARTED:
					//when we change the media we can reset the loadMediaOnPlay flag
					var designatedEntryId : String = String(note.getBody().entryId);
					
					_loadMediaOnPlay = false;
					_alertCalled = false;
					player.removeEventListener( TimeEvent.COMPLETE , onTimeComplete );
					_isIntelliSeeking = false;
					
					//Fixed weird issue, where the CHANGE_MEDIA would be caught by the mediator 
					// AFTER the new media has already loaded. Caused media never to be loaded.
					if (designatedEntryId != _mediaProxy.vo.entry.id)
					{
						kMediaPlayer.unloadThumbnail()
						cleanMedia();
					}
				break;
				case NotificationType.DO_PLAY: //when the player asked to play	
					
					if (_mediaProxy.vo.entry is KalturaLiveStreamEntry || _mediaProxy.vo.deliveryType == StreamerType.LIVE)
					{
						if (_mediaProxy.vo.isOffline)
						{
							return;
						}
					}
					
					if(_mediaProxy.vo.entry.id && _mediaProxy.vo.entry.id!= "-1" && sequenceProxy.hasSequenceToPlay() )
					{
						sequenceProxy.vo.isInSequence = true;
						sequenceProxy.playNextInSequence();
						return;
					}
					else if (!_mediaProxy.vo.media || player.media != _mediaProxy.vo.media)
					{
						//_mediaProxy.prepareMediaElement();
						_mediaProxy.loadWithMediaReady();
						return;
					}
					else if(_mediaProxy.vo.entry is KalturaMixEntry && 
							player.media.getTrait(MediaTraitType.DISPLAY_OBJECT)["isReadyForLoad"] &&
							!player.media.getTrait(MediaTraitType.DISPLAY_OBJECT)["isSpriteLoaded"])
					{
						player.media.getTrait(MediaTraitType.DISPLAY_OBJECT)["loadAssets"]();
						_mixLoaded = true;
						
						/////////////////////////////////////////////
						//TODO: why we need to send play again ? we should change thos if else statment and use return if needed, 
						//but to send DO_PLAY again it's a bug 
						sendNotification(NotificationType.DO_PLAY); 
						/////////////////////////////////////////////
					}
					else if(player.canPlay) 
					{
						var timeTrait : TimeTrait = _mediaProxy.vo.media.getTrait(MediaTraitType.TIME) as TimeTrait;

						if( _mediaProxy.vo.entryExtraData && !_mediaProxy.vo.entryExtraData.isAdmin && 
						    (_mediaProxy.vo.entryExtraData.isCountryRestricted ||
							!_mediaProxy.vo.entryExtraData.isScheduledNow ||
							_mediaProxy.vo.entryExtraData.isSiteRestricted ||
							(_mediaProxy.vo.entryExtraData.isSessionRestricted && _mediaProxy.vo.entryExtraData.previewLength <= 0)))
						{
							return;
						}
						
						//if it's Entry and the entry id empty or equal -1 don't play
	 					if( _flashvars.sourceType == SourceType.ENTRY_ID &&
							(_mediaProxy.vo.entry.id == null || _mediaProxy.vo.entry.id == "-1"))
						{
							return;
						} 
						
						if(_currentTime >= _duration){
							sendNotification(NotificationType.DO_REPLAY);
							sendNotification(NotificationType.DO_SEEK,0);
							player.addEventListener(TimeEvent.COMPLETE, onTimeComplete);
							
						}
						
						//if we did intelligent seek and reach the end of the movie we must load the new url
						//back form 0 before we can play
						if(_loadMediaOnPlay)
						{
							_loadMediaOnPlay = false;
							_mediaProxy.prepareMediaElement(0);
							_mediaProxy.vo.singleAutoPlay = true;
							return;		
						}
						
						
						
						playContent();
					}
					else //not playable
					{
						//if we play image that not support duration we should act like we play somthing static
						if(	_mediaProxy.vo.entry is KalturaMediaEntry && _mediaProxy.vo.entry.mediaType==KalturaMediaType.IMAGE)				
							sendNotification( NotificationType.PLAYER_PLAYED);	
					}
				break;
				
				case LiveStreamCommand.LIVE_STREAM_READY: 
					//this means that this is a live stream and it is broadcasting now
					cleanMedia();
					_mediaProxy.vo.isOffline = false;
					if (_mediaProxy.vo.singleAutoPlay) {
						sendNotification(NotificationType.DO_PLAY);
						_mediaProxy.vo.singleAutoPlay = false;
					}
				break;
				case NotificationType.CLEAN_MEDIA:
					cleanMedia();
				break;
				case NotificationType.DO_SWITCH:
					var preferedFlavorBR:int = int(note.getBody());
					
					if(player.isDynamicStream) // rtmp adaptive mbr
					{
						//we need to set the mediaProxy prefered 

						//i have added it only here because it happen in CHANGE_MEDIA as well
						var dynamicStreamTrait : DynamicStreamTrait;
						if (player.media.hasTrait(MediaTraitType.DYNAMIC_STREAM))
						{
							dynamicStreamTrait = player.media.getTrait(MediaTraitType.DYNAMIC_STREAM) as DynamicStreamTrait;
						}
						if (dynamicStreamTrait && !dynamicStreamTrait.switching)
						{
							if(preferedFlavorBR || preferedFlavorBR == -1)
								_mediaProxy.vo.preferedFlavorBR = preferedFlavorBR;
								
							
							if(!_hasPlayed){
								_mediaProxy.vo.switchDue = true;
								return;
							}
							//var foundStreamIndex:int = _mediaProxy.findDynamicStreamIndexByProp(preferedFlavorBR , "bitrate");
							var foundStreamIndex:int = kMediaPlayer.findStreamByBitrate(preferedFlavorBR);
							trace("Found stream index:", foundStreamIndex);
							trace("Current stream index: ", player.currentDynamicStreamIndex);
							if (foundStreamIndex == -1)
							{
								player.autoDynamicStreamSwitch = true;
	
							}
							else if (foundStreamIndex != player.currentDynamicStreamIndex)
							{
								player.autoDynamicStreamSwitch = false;
								player.switchDynamicStreamIndex(foundStreamIndex);
								sendNotification( NotificationType.SWITCHING_CHANGE_STARTED, {newIndex: foundStreamIndex, newBitrate: foundStreamIndex != -1 ? player.getBitrateForDynamicStreamIndex(foundStreamIndex): null} );
							}
						}
					}
					else // change media
					{
						_mediaProxy.vo.singleAutoPlay = true;
						sendNotification( NotificationType.CHANGE_MEDIA, {entryId: _mediaProxy.vo.entry.id, flavorId: null, preferedFlavorBR: preferedFlavorBR });
					}
				break;
				case NotificationType.DO_STOP: //when the player asked to stop
					sendNotification( NotificationType.DO_PAUSE );
					sendNotification( NotificationType.DO_SEEK , 0 );
				break;
				case NotificationType.DO_PAUSE: //when the player asked to pause
					//_actuallyPlays=false;
					if(player && player.media && player.media.hasTrait(MediaTraitType.PLAY) )
					{
						if (player.canPause)
						{
							player.pause();
						}
						if (_mediaProxy.vo.entry is KalturaLiveStreamEntry || _mediaProxy.vo.deliveryType == StreamerType.LIVE)
						{
							player.stop();
						}
					}
				break;
				case NotificationType.DO_SEEK: //when the player asked to seek
					
					var seekTo : Number = Number(note.getBody());
					//_isIntelliSeeking = false;
					//check if we have free preview and we ask to seek to later time
					//we should not allow the seek. 
					if( _mediaProxy.vo.entryExtraData && 
					   !_mediaProxy.vo.entryExtraData.isAdmin && 
					   _mediaProxy.vo.entryExtraData.isSessionRestricted &&
						_mediaProxy.vo.entryExtraData.previewLength != -1 &&
						_mediaProxy.vo.entryExtraData.previewLength <= Number(note.getBody()))
					{
						return;
					}
					if (!player.canSeek) 
					{
						return;
					}
					
					if(_flashvars.streamerType!=StreamerType.HTTP)
					{
						
						if(player.canSeek) player.seek( Number(note.getBody())  );
						return;	
					}
					
					
					if ( (_mediaProxy.vo.entry is KalturaMixEntry) ||
						(Number(note.getBody()) <= _loadedTime  && !_isIntelliSeeking))
					{
						if(player.canSeek) player.seek( Number(note.getBody())  ); 
						
					}
					else //do intlliseek
					{		 
						if(!_mediaProxy.vo.keyframeValuesArray) return;
						
						 _isIntelliSeeking = true; 
						_offset = Number(note.getBody())
					   
				        //on a new seek we can reset the load media on play flag
				        _loadMediaOnPlay = false;
				        
				        //_seekUrl=_mediaProxy.convertToIntSeek(_url,_offset)
				        _mediaProxy.vo.entry.dataUrl=_seekUrl;
				        _mediaProxy.prepareMediaElement( _offset);
						_mediaProxy.loadWithMediaReady();
						_intelliSeekStart = seekTo;
						sendNotification( NotificationType.INTELLI_SEEK,{intelliseekTo: _offset} );
					}
					
				break;
				
				case NotificationType.CHANGE_VOLUME:  //when the player asked to set new volume point
					kMediaPlayer.volume = ( Number(note.getBody()) ); 
				break;
				case NotificationType.KDP_READY:
				case NotificationType.KDP_EMPTY:
					var preloaderMediator : BufferAnimationMediator = facade.retrieveMediator( BufferAnimationMediator.NAME ) as BufferAnimationMediator;
					kMediaPlayer.bufferSprite = preloaderMediator.spinner; 
					if(_autoMute)
					{
						sendNotification(NotificationType.CHANGE_VOLUME, 0);	
					}
				break;
				case NotificationType.PLAYER_SEEK_START:
					if (player.state != MediaPlayerState.PAUSED)
					{
						_mediaProxy.vo.singleAutoPlay = true;
						_prevState = "playing";
					}
					else
					{
						_mediaProxy.vo.singleAutoPlay = false;
						_prevState = "paused";
					}
					break;
			}
		}
		
				
		/**
		 * Get a reference to the kMediaPlayer
		 * @return 
		 * 
		 */	
		public function get kMediaPlayer():KMediaPlayer
		{
			return (viewComponent as KMediaPlayer);	
		}
		
		/**
		 * Get a reference to the OSMF player (inner event dispatcher of the KMediaPlayer)
		 * @return 
		 * 
		 */		
		public function get player():MediaPlayer
		{
			return (viewComponent as KMediaPlayer).player;	
		}
		
		/**
		 * Play the media in the player. 
		 * 
		 */		
		public function playContent() : void
		{
			player.play();
		}

		/**
		 * Sets the  MediaElement of the player.
		 * 
		 */		
		public function setSource() : void
		{
			var sequenceProxy : SequenceProxy = facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy;
			if(_mediaProxy.vo && _mediaProxy.vo.media)
			{
				player.media = _mediaProxy.vo.media; //set the current media to the player	
			}	
			
			
			if(player.state != MediaPlayerState.PLAYING)
			{
				if( _mediaProxy.vo.entryExtraData && !_mediaProxy.vo.entryExtraData.isAdmin && 
				    (_mediaProxy.vo.entryExtraData.isCountryRestricted ||
					!_mediaProxy.vo.entryExtraData.isScheduledNow ||
					_mediaProxy.vo.entryExtraData.isSiteRestricted ||
					(_mediaProxy.vo.entryExtraData.isSessionRestricted && _mediaProxy.vo.entryExtraData.previewLength <= 0)))
				{
					_blockThumb = true;
				}
				else
				{
					_blockThumb = false;
				}
			}
			
		}
		
		
		//private functions
		////////////////////////////////////////////
		
		/**
		 * describe the current state of the Media Player. 
		 * @param event
		 * 
		 */		
		private function onPlayerStateChange( event : MediaPlayerStateChangeEvent ) : void
		{	
			sendNotification( NotificationType.PLAYER_STATE_CHANGE , event.state );
			var sequenceProxy : SequenceProxy = facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy;
			//trace(event.state)
			switch( event.state )
			{
				case MediaPlayerState.LOADING:
					
					// The following if-statement provides a work-around for using the mediaPlayFrom parameter for http-streaming content. Currently
					//  a bug exists in the Akamai Advanced Streaming plugin which prevents a more straight-forward implementation.
					if (_mediaProxy.vo.mediaPlayFrom && !sequenceProxy.vo.isInSequence && _mediaProxy.vo.deliveryType == StreamerType.HDNETWORK)
					{
						player.addEventListener(MediaPlayerCapabilityChangeEvent.CAN_SEEK_CHANGE, onCanSeekChange);
					}
					break;
				case MediaPlayerState.READY: 
					if(! player.hasEventListener(TimeEvent.COMPLETE))
						player.addEventListener( TimeEvent.COMPLETE , onTimeComplete );
					
					if(!_playerReadyOrEmptyFlag)
					{
						_playerReadyOrEmptyFlag = true;
						var playerStatusProxy : PlayerStatusProxy = facade.retrieveProxy(PlayerStatusProxy.NAME) as PlayerStatusProxy;	
					}
					else
					{
						sendNotification( NotificationType.PLAYER_READY ); 
					}
					
					_mediaProxy.loadComplete();
					//sendNotification(NotificationType.MEDIA_READY, {entryId: _mediaProxy.vo.entry.id});
				break;
				case MediaPlayerState.PAUSED:
					sendNotification( NotificationType.PLAYER_PAUSED );	
				    break;

				case MediaPlayerState.PLAYING: 
					
					 
				     if(!_hasPlayed){
				     	_hasPlayed = true;
				     }
					 
					 if (player.media != null && _mediaProxy.vo.mediaPlayFrom && !sequenceProxy.vo.isInSequence && _mediaProxy.vo.deliveryType != StreamerType.HDNETWORK)
					 {				
						 startClip();
					 }
				     //If the player is playing RTMP content and the user switched bitrates before the entry started playing
				     // it causes a OSMF bug.  the bug is fixed by saving the switch until the play button is pressed
				     if(player.isDynamicStream)
				     {
				     	if(_mediaProxy.vo.switchDue)
				     	{
				     		_mediaProxy.vo.switchDue = false;
				     		sendNotification(NotificationType.DO_SWITCH, _mediaProxy.vo.preferedFlavorBR);
				     	}
				     }
					 
					//if this is Audio and not blocked entry countinue to show the Thumbnail
					if(_mediaProxy.vo.entry.mediaType==KalturaMediaType.AUDIO && !_blockThumb &&!sequenceProxy.vo.isInSequence)
						kMediaPlayer.showThumbnail();
					else //else hide the thumbnail
						kMediaPlayer.hideThumbnail();
						
					
					sendNotification( NotificationType.PLAYER_PLAYED );
					if (_prevState == "paused" && _isIntelliSeeking)
					{
						sendNotification(NotificationType.DO_PAUSE);
						_prevState ="";
					}
					
					
				break;
				case MediaPlayerState.PLAYBACK_ERROR:
					if (_flashvars.debugMode == "true")
					{
						trace("KMediaPlayerMediator :: onPlayerStateChange >> osmf mediaplayer playback error.");
					}
				break;
				
				
			}
		}
		
		//////////////////////////////////////////////////////////
		/* The following block of code is a work-around for */
		/* using the mediaPlayFrom parameter for http-streaming
		 * content. It will be removed when the Akamai Advanced
		 * streaming plugin will be fixed to support this scenario.*/
	
		private function onCanSeekChange(event:MediaPlayerCapabilityChangeEvent):void
		{	
			//player.removeEventListener (MediaPlayerCapabilityChangeEvent.CAN_SEEK_CHANGE, onCanSeekChange);
			if (player.media != null && _mediaProxy.vo.mediaPlayFrom)
			{		
				if (_mediaProxy.vo.deliveryType == StreamerType.HDNETWORK)
				{
					
					setTimeout(startClip, 100 );
				}
			}
			
		}

		private function startClip () : void
		{
			if (_mediaProxy.vo.mediaPlayFrom)
			{
				var temp : Number = _mediaProxy.vo.mediaPlayFrom;
				_mediaProxy.vo.mediaPlayFrom = 0;
				sendNotification( NotificationType.DO_SEEK, temp );
				
			}
		}
		//////////////////////////////////////////////////////////////////////
		
	
		
		/**
		 * Dispatched when a MediaPlayer's ability to expose its media as a DisplayObject has changed
		 * @param event
		 * 
		 */		
		private function onViewableChange( event : DisplayObjectEvent ) : void
		{
			sendNotification( NotificationType.MEDIA_VIEWABLE_CHANGE );
		}
		
		/**
		 * dispatches when the player width and/or  height properties have changed. 
		 * @param event
		 * 
		 */		
		private function  onMediaSizeChange( event : DisplayObjectEvent ) :void
		{
			if(_flashvars.sourceType==SourceType.URL)
				kMediaPlayer.setContentDimension(event.newWidth, event.newHeight);
				
			kMediaPlayer.validateNow();
		}
		
		/**
		 * A MediaPlayer dispatches this event when its playhead property has changed. 
		 * This value is updated at the interval set by the MediaPlayer's playheadUpdateInterval property.  
		 * @param event
		 * 
		 */		
		private function onPlayHeadChange( event : TimeEvent ) : void
		{
			
			if (player.temporal)
			{
				sendNotification( NotificationType.PLAYER_UPDATE_PLAYHEAD , event.time );
				//trace("updating ",event.time);
				var sequenceProxy: SequenceProxy = facade.retrieveProxy(SequenceProxy.NAME) as SequenceProxy;
				
				if (sequenceProxy.vo.isInSequence)
				{
					var duration : Number = (player.media.getTrait(MediaTraitType.TIME) as TimeTrait).duration;
					sequenceProxy.vo.timeRemaining = (Math.round(duration - event.time) > 0) ? Math.round(duration - event.time) : 0;	
				}
				if( !isNaN(event.time) )
				{
					_currentTime=event.time;
				}
				
				if (_mediaProxy.vo.mediaPlayTo)
				{
					if (_mediaProxy.vo.mediaPlayTo <= event.time)
					{
						_mediaProxy.vo.mediaPlayTo = 0;
						sendNotification(NotificationType.DO_PAUSE );
					}
				}
				
				if( _mediaProxy.vo.entryExtraData && 
					!_mediaProxy.vo.entryExtraData.isAdmin && 
					_mediaProxy.vo.entryExtraData.isSessionRestricted && 
					_mediaProxy.vo.entryExtraData.previewLength != -1 &&
					(_mediaProxy.vo.entryExtraData.previewLength-0.2) <= event.time &&
					 !sequenceProxy.vo.isInSequence &&
					!_alertCalled)
				{
					_alertCalled = true;
					//pause the player
					sendNotification( NotificationType.DO_PAUSE );
					

					//show alert
					sendNotification( NotificationType.ALERT , {message: MessageStrings.getString('FREE_PREVIEW_END'), title: MessageStrings.getString('FREE_PREVIEW_END_TITLE')} );
					//call the page with the entry is in sig
					//var extProxy : ExternalInterfaceProxy = facade.retrieveProxy( ExternalInterfaceProxy.NAME ) as ExternalInterfaceProxy;
					sendNotification( NotificationType.FREE_PREVIEW_END , _mediaProxy.vo.entry.id );
					//disable GUI
					//sendNotification( NotificationType.ENABLE_GUI , {guiEnabled : false , enableType : EnableType.CONTROLS} );
					
				}
			}
		}

		
		/**
		 * A trait that implements the IAudible interface dispatches this event when its volume property has changed.  
		 * @param event
		 * 
		 */		
		private function onVolumeChangeEvent( event : AudioEvent ) : void
		{
			sendNotification( NotificationType.VOLUME_CHANGED , {newVolume:event.volume});
		}
		
		/**
		 * Dispatch the old time and the new time of the buffering 
		 * @param event
		 * 
		 */		
		private function onBufferTimeChange( event : BufferEvent ) : void
		{
			sendNotification( NotificationType.BUFFER_PROGRESS , {newTime:event.bufferTime} );
		}
		
		/**
		 * When the player start or stop the buffering 
		 * @param event
		 * 
		 */		
		private function onBufferingChange( event : BufferEvent ) : void
		{
			sendNotification( NotificationType.BUFFER_CHANGE , event.buffering );
		}
		/**
		 * The current and previous value of bytesDownloaded dispatches this event when bytes currently downloaded change 
		 * @param event
		 * 
		 */		
		private function onBytesDownloadedChange( event : LoadEvent ) : void
		{
            _bytesLoaded=event.bytes;
            _loadedTime=(_bytesLoaded/_bytesTotal)*_duration;
			sendNotification( NotificationType.BYTES_DOWNLOADED_CHANGE , {newValue:event.bytes} );
		}
		
		/**
		 * dispatched by a concrete implementation of IDownloadable when the value of the property "bytesTotal" has changed. 
		 * @param event
		 * 
		 */		
		private function onBytesTotalChange( event : LoadEvent ) : void
		{
			_bytesTotal=event.bytes;
			sendNotification( NotificationType.BYTES_TOTAL_CHANGE , {newValue:event.bytes} );
		}

		/**
		 * A trait that implements the ITemporal interface dispatches this event when its duration property has changed
		 * @param event
		 * 
		 */		
		private function onDurationChange( event : TimeEvent ) : void
		{
			if(!_isIntelliSeeking && event.time)
			{
				_duration=event.time
				sendNotification( NotificationType.DURATION_CHANGE , {newValue:_duration});
			}
			
			
		}
		/**
		 * Dispatched when the position  of a trait that implements the ITemporal interface first matches its duration. 
		 * @param event
		 * 
		 */		
		private function onTimeComplete( event : TimeEvent ) : void
		{
 			if(event.type == TimeEvent.COMPLETE)
			{
				//ssendNotification(NotificationType.DO_PAUSE);
				player.removeEventListener(TimeEvent.COMPLETE, onTimeComplete);
				//sendNotification(NotificationType.DO_PAUSE);
				if( _isIntelliSeeking ){
					_isIntelliSeeking = false;
					_loadedTime=0;
					_loadMediaOnPlay = true;
				}	
				
				sendNotification(NotificationType.PLAYBACK_COMPLETE);
				
		 	
	 		}
			
			//_actuallyPlays=false;	
		}
		/**
		 * A MediaElement dispatches a MediaErrorEvent when it encounters an error.  
		 * @param event
		 * 
		 */		
		private function onMediaError( event : MediaErrorEvent ) : void
		{
			sendNotification( NotificationType.MEDIA_ERROR , event.error );
		}
		
		/**
		 * 
		 * @param event
		 * 
		 */		
		private function onSwitchingChange( event : DynamicStreamEvent ) : void
		{
			//trace(event.detail ? (event.detail.description + " " + event.detail.moreInfo) : "no details");
			trace("DynamicStreamEvent ===> " , event.type , player.currentDynamicStreamIndex);
			if (!event.switching)
			{
				sendNotification( NotificationType.SWITCHING_CHANGE_COMPLETE, {newIndex : player.currentDynamicStreamIndex, newBitrate: player.getBitrateForDynamicStreamIndex(player.currentDynamicStreamIndex)}  );
			}
			else if (player.autoDynamicStreamSwitch)
			{
				sendNotification( NotificationType.SWITCHING_CHANGE_STARTED, {currentIndex : player.currentDynamicStreamIndex, currentBitrate: player.getBitrateForDynamicStreamIndex(player.currentDynamicStreamIndex)});
			}
		}
		
		/**
		 * Function which removed the current media element from the 
		 * OSMF media player.
		 * 
		 */		
		public function cleanMedia():void
		{
			//we don't need to clean the media if it's empty
			
			if(!player.media) return;
			
			if (player.media.hasOwnProperty("cleanMedia"))
				sendNotification( NotificationType.DO_STOP );
			
			if(player.displayObject)
			{
		   		player.displayObject.height=0;////this is for clear the former clip...
		  		player.displayObject.width=0;///this is for clear the former clip...
			}

						
			player.media = null;
		}
		
		/**
		 * reference to the player container 
		 * @return 
		 * 
		 */		
		public function get playerContainer () : DisplayObjectContainer
		{
			return viewComponent as DisplayObjectContainer;	
		}
		
		
		public function get isIntelliSeeking():Boolean
		{
			return _isIntelliSeeking;
		}

		

	}
}