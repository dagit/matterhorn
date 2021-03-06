module Command where

import Brick (EventM, Next, continue, halt)
import Control.Monad (void, when)
import Control.Monad.IO.Class (liftIO)
import Data.Monoid ((<>))
import qualified Data.Text as T

import Lens.Micro.Platform

import Network.Mattermost
import Network.Mattermost.Lenses

import State
import Types

data Cmd = Cmd
  { commandName   :: T.Text
  , commandDescr  :: T.Text
  , commandAction :: [T.Text] -> ChatState -> EventM Name (Next ChatState)
  }

commandList :: [Cmd]
commandList =
  [ Cmd "quit" "Exit Matterhorn" $ \ _ st -> halt st
  , Cmd "right" "Focus on the next channel" $ \ _ st ->
      nextChannel st >>= continue
  , Cmd "left" "Focus on the previous channel" $ \ _ st ->
      prevChannel st >>= continue
  , Cmd "theme" "Set the color theme" $ \ args st ->
      case args of
          []          -> listThemes st >>= continue
          [themeName] -> setTheme st themeName >>= continue
          _           -> continue st
  , Cmd "topic" "Set the current channel's topic" $ \ args st -> do
      when (not $ null args) $ do
          let p = T.unwords args
          liftIO $ setChannelTopic st p
      continue st
  , Cmd "focus" "Focus on a named channel" $ \ [name] st ->
      case channelByName st name of
        Just cId -> setFocus cId st >>= continue
        Nothing -> do
          msg <- newClientMessage Error ("No channel or user named " <> name)
          continue =<< addClientMessage msg st
  , Cmd "help" "Print the help dialogue" $ \ _ st -> do
          continue $ st & csMode .~ ShowHelp
  ]

dispatchCommand :: T.Text -> ChatState -> EventM Name (Next ChatState)
dispatchCommand cmd st =
  case T.words cmd of
    (x:xs) | [ c ] <- [ c | c <- commandList
                          , commandName c == x
                          ] -> commandAction c xs st
           | otherwise ->
             execMMCommand cmd st >>= continue
    _ -> continue st

setChannelTopic :: ChatState -> T.Text -> IO ()
setChannelTopic st msg = do
    let chanId = currentChannelId st
        theTeamId = st^.csMyTeam.teamIdL
    doAsyncWith st $ do
        void $ mmSetChannelHeader (st^.csConn) (st^.csTok) theTeamId chanId msg
        return $ \st' -> do
            return $ st' & msgMap.at chanId.each.ccInfo.cdHeader .~ msg
