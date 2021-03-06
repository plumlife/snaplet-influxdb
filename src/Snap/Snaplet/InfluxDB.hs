{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}

module Snap.Snaplet.InfluxDB
  ( initInflux
  , runInflux
  , runInfluxPost
  , mkInfluxPool
  , InfluxState   (..)
  , HasInfluxPool (..)
  ) where

import           Control.Monad.State
import           Control.Monad.Trans.Reader
import           Data.Configurator
import           Data.Configurator.Types    as CT
import           Data.Text                  (Text)
import           Database.InfluxDB          as IN
import           Network.HTTP.Client
import           Paths_snaplet_influxdb
import           Snap.Snaplet

-------------------------------------------------------------------------------
data InfluxPool = InfluxPool DB IN.Config

type DB = Text

newtype InfluxState = InfluxState { influxPool :: InfluxPool }

-------------------------------------------------------------------------------
class MonadIO m => HasInfluxPool m where
    getInfluxPool :: m InfluxPool

instance HasInfluxPool (Handler b InfluxState) where
    getInfluxPool = gets influxPool

instance MonadIO m => HasInfluxPool (ReaderT InfluxPool m) where
    getInfluxPool = ask

-- | Initialize the Influx Snaplet.
initInflux :: SnapletInit b InfluxState
initInflux = makeSnaplet "influxdb" description datadir $ do
    p <- mkSnapletInfluxPool

    let (InfluxPool _ c) = p
        mgr              = configHttpManager c

    onUnload (closeManager mgr)

    return $ InfluxState p

  where
    description = "Snaplet for the InfluxDB library"
    datadir = Just $ liftM (++"/resources/influxdb") getDataDir

-------------------------------------------------------------------------------
-- | Constructs a connection in a snaplet context.
mkSnapletInfluxPool :: (MonadIO (m b v), MonadSnaplet m) => m b v InfluxPool
mkSnapletInfluxPool = do
  conf <- getSnapletUserConfig
  mkInfluxPool conf

-------------------------------------------------------------------------------
-- | Constructs a connect from Config.
mkInfluxPool :: MonadIO m => CT.Config -> m InfluxPool
mkInfluxPool conf = do
  host' <- liftIO $ require conf "host"
  port' <- liftIO $ require conf "port"
  ssl   <- liftIO $ require conf "ssl"
  db    <- liftIO $ require conf "db"
  user  <- liftIO $ require conf "user"
  pass  <- liftIO $ require conf "pass"

  mgr   <- liftIO $ newManager defaultManagerSettings
  pool  <- liftIO $ newServerPool (Server host' port' ssl) []

  let cnf = Config (Credentials user pass) pool mgr

  return $ InfluxPool db cnf

-------------------------------------------------------------------------------
-- | Runs an INFLUX action in any monad with a HasInfluxPool instance.
runInflux :: (HasInfluxPool m) => (IN.Config -> IO r) -> m r
runInflux action = do
    (InfluxPool _ pool) <- getInfluxPool
    liftIO $! action pool

-------------------------------------------------------------------------------
-- | Runs an INFLUX action in any monad with a HasInfluxPool instance.
runInfluxPost :: (HasInfluxPool m) => [Line] -> m ()
runInfluxPost series = do
    (InfluxPool db pool) <- getInfluxPool
    liftIO $ postWithPrecision pool db SecondsPrecision series
