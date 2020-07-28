{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE TemplateHaskell           #-}

import           Composite.Record
import Data.Hashable.Time
import qualified Data.IxSet.Typed             as Ix
import qualified Data.IxSet.Typed.Conversions as Ix
import           Data.List.Split
import           Data.Text.Time
import           Development.Shake.Plus.Extended
import           Lucid
import           Path.Extensions
import           RIO
import           RIO.List
import           RIO.List.Partial
import           RIO.Partial
import qualified RIO.Text                     as T
import qualified RIO.Text.Partial             as T
import           Shakebook                    hiding ((:->))
import           Shakebook.Utils
import           Test.Tasty
import           Test.Tasty.Golden

sourceFolder :: Path Rel Dir
sourceFolder = $(mkRelDir "test/site")

outputFolder :: Path Rel Dir
outputFolder = $(mkRelDir "test/public")

baseUrl :: Text
baseUrl = "http://blanky.test"

siteTitle :: Text
siteTitle = "Blanky Site"

tableOfContents :: Cofree [] (Path Rel File)
tableOfContents = $(mkRelFile "docs/index.html") :< [
                    $(mkRelFile "docs/1/index.html") :< []
                  , $(mkRelFile "docs/2/index.html") :< [
                  $(mkRelFile "docs/2/champ.html") :< []
                    ]
                  ]

numRecentPosts :: Int
numRecentPosts = 3

postsPerPage :: Int
postsPerPage = 5

mySocial :: [Record Link]
mySocial = ["twitter" :*: "http://twitter.com/blanky-site-nowhere" :*: RNil
           ,"youtube" :*: "http://youtube.com/blanky-site-nowhere" :*: RNil
           ,"gitlab"  :*: "http://gitlab.com/blanky-site-nowhere" :*: RNil]

myBlogNav :: (Ix.IsIndexOf YearMonth ixs, RElem FPosted xs, RElem FUrl xs, RElem FTitle xs)
          => Ix.IxSet ixs (Record xs)
          -> Html ()
myBlogNav = genBlogNav "Blog" "/posts/" defaultPrettyMonthFormat defaultMonthUrlFragment

myDocNav :: (RElem FUrl xs, RElem FTitle xs) => Cofree [] (Record xs) -> Html ()
myDocNav = genDocNav

addUrl :: (MonadThrow m, RElem FSrcPath xs) => Record xs -> m (Record (FUrl : xs))
addUrl = addDerivedUrl (fmap toGroundedUrl . withHtmlExtension <=< stripProperPrefix sourceFolder)

addTagLinks :: RElem FTags xs => Record xs -> Record (FTagLinks : xs)
addTagLinks xs = (fmap (\x -> x :*: ("/posts/tags/" <> x) :*: RNil) . viewTags $ xs ) :*: xs

addTeaser :: RElem FContent xs => Record xs -> Record (FTeaser : xs)
addTeaser xs = head (T.splitOn "<!-- more -->" (viewContent xs)) :*: xs

addPrettyDate :: RElem FPosted xs => Record xs -> Record (FPrettyDate : xs)
addPrettyDate xs = viewPosted xs :*: xs

stage1Post :: (MonadAction m, MonadThrow m) => Record RawPost -> m (Record Stage1Post)
stage1Post = addUrl >=> return . addPrettyDate . addTagLinks . addTeaser

stage1Doc :: MonadThrow m => Record RawDoc -> m (Record Stage1Doc)
stage1Doc = addUrl

enrichPage :: Record x -> Record (Enriched x)
enrichPage x = mySocial :*: defaultCdnImports :*: defaultHighlighting :*: siteTitle :*: x

data SimpleSPlus = SimpleSPlus {
  logFunc :: LogFunc
, localOut :: Path Rel Dir
}

instance HasLogFunc SimpleSPlus where
  logFuncL = lens logFunc undefined

instance HasLocalOut SimpleSPlus where
  localOutL = lens localOut undefined

newtype BlogNav = BlogNav ()
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

newtype RecentPosts = RecentPosts ()
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

newtype PostZipper = PostZipper ()
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

instance NFData (Html ()) where
  rnf a = seq a ()

type instance RuleResult BlogNav = Html ()

type instance RuleResult Tag = Ix.IxSet '[Tag, Posted, YearMonth] (Record Stage1Post)

type instance RuleResult RecentPosts = [Record Stage1Post]

newtype PostsRoot = PostsRoot ()
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult PostsRoot = Text

newtype TagRoot = TagRoot Tag
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult TagRoot = Text

newtype YearMonthRoot = YearMonthRoot YearMonth
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult YearMonthRoot = Text

newtype PostPages = PostPages ()
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult PostPages = [Record (FUrl : FItems Stage1Post : FPageNo : '[])]

newtype TagPages = TagPages Tag
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult TagPages = [Record (FUrl : FItems Stage1Post : FPageNo : '[])]

newtype YearMonthPages = YearMonthPages YearMonth
  deriving (Eq, Show, Generic, Binary, Hashable, NFData)

type instance RuleResult YearMonthPages = [Record (FUrl : FItems Stage1Post : FPageNo : '[])]

rules :: ShakePlus SimpleSPlus ()
rules = do

  readMD <- newCache $ \x -> do
    logInfo $ "Loading " <> displayShow (toFilePath x)
    loadMarkdownAsJSON defaultMarkdownReaderOptions defaultHtml5WriterOptions x

  readRawSingle <- newCache $ readMD >=> parseValue' rawSingleJsonFormat
  readRawPost   <- newCache $ readMD >=> parseValue' rawPostJsonFormat
  readRawDoc    <- newCache $ readMD >=> parseValue' rawDocJsonFormat

  readStage1Post <- newCache $ readRawPost >=> stage1Post
  readStage1Doc  <- newCache $ readRawDoc  >=> stage1Doc

  postIx' <- newCache $ \() -> batchLoadIndex' (Proxy @[Tag, Posted, YearMonth]) readStage1Post sourceFolder ["posts/*.md"]

  addOracle $ \(PostsRoot ())                      -> return "/posts/"
  addOracle $ \(TagRoot (Tag t))                   -> askOracle (PostsRoot ()) >>= \x -> return (x <> "tags/" <> t <> "/")
  addOracle $ \(YearMonthRoot (YearMonth (y,m))) -> askOracle (PostsRoot ()) >>= \x -> return (x <> "months/" <> defaultMonthUrlFormat (fromYearMonthPair (y, m)) <> "/")

  let indexPages q ps = do
        r <- askOracle q
        k <- Ix.toDescList (Proxy @Posted) <$> ps
        p <- paginate' postsPerPage k
        return $ unzipper $ extend (\x -> r <> "pages/" <> T.pack (show $ pos x + 1) :*: extract x :*: pos x + 1:*: RNil) p

  addOracleCache $ \(PostPages ())      -> indexPages (PostsRoot ()) (postIx' ())
  addOracleCache $ \(TagPages x)        -> indexPages (TagRoot x) ((Ix.@+ [x]) <$> postIx' ())
  addOracleCache $ \(YearMonthPages x)  -> indexPages (YearMonthRoot x) ((Ix.@+ [x]) <$> postIx' ())

  addOracleCache $ \(BlogNav ()) -> myBlogNav <$> postIx' ()

  addOracleCache $ \(RecentPosts ()) -> take numRecentPosts . Ix.toDescList (Proxy @Posted) <$> postIx' ()

  let correspondingMD   = withMdExtension . (sourceFolder </>)

      getDoc   = correspondingMD >=> readStage1Doc

      docNav   = myDocNav <$> mapM getDoc tableOfContents

  "index.html" /%> \(dir, fp) -> do
    v   <- readRawSingle =<< correspondingMD fp
    xs  <- askOracle $ RecentPosts ()
    let (v' :: TMain) = Val $ xs :*: enrichPage v
    buildPageAction' sourceFolder v' mainPageJsonFormat $ dir </> fp

  "posts/*.html" /%> \(dir, fp) -> do
    src <- correspondingMD fp
    xs  <- postIx' () >>= Ix.toZipperDesc (Proxy @Posted) >>= seekOnThrow viewSrcPath src
    nav <- askOracle $ BlogNav ()
    let (v :: TPost) = Val $ nav :*: enrichPage (extract xs)
    buildPageAction' sourceFolder v finalPostJsonFormat $ dir </> fp

  sequence_ $ tableOfContents =>> \xs ->
    (toFilePath . extract $ xs) /%> \(dir, fp) -> do
      nav  <- docNav
      subs <- mapM getDoc (fmap extract . unwrap $ xs)
      v    <- getDoc fp
      let (v' :: TDoc) = Val $ nav :*: subs :*: enrichPage v
      buildPageAction' sourceFolder v' finalDocJsonFormat $ dir </> fp

  let buildPostIndex title query pageno out = do
        nav <- askOracle $ BlogNav ()
        xs  <- askOracle query
        xs' <- zipper' $ sortOn (Down . viewPageNo) xs
        let links = fmap (\x ->  T.pack (show (viewPageNo x)) :*: viewUrl x :*: RNil) (unzipper xs')
        let (v :: TPostIndex) = Val $ enrichPage (links :*: nav :*: title :*: extract (seek (pageno - 1) xs'))
        buildPageAction' sourceFolder v postIndexPageJsonFormat out

  "posts/pages/*/index.html" /%> \(dir, fp) -> do
    let n = read . (!! 2) $ splitPath fp
    buildPostIndex "Posts" (PostPages ()) n $ dir </> fp

  "posts/tags/*/pages/*/index.html" /%> \(dir, fp) -> do
    let fp' = splitPath fp
    let t = T.pack $ fp' !! 2
    let n = read   $ fp' !! 4
    buildPostIndex ("Posts tagged " <> t) (TagPages (Tag t)) n $ dir </> fp

  "posts/months/*/pages/*/index.html" /%> \(dir, fp) -> do
    let out' = splitPath fp
    let t  = parseISODateTime $ T.pack $ out' !! 2
    let t' = YearMonth $ toYearMonthPair t
    let n  = read $ out' !! 4
    buildPostIndex ("Posts from " <> defaultPrettyMonthFormat t) (YearMonthPages t') n $ dir </> fp

  "posts/index.html" /%> \(dir, fp) ->
    copyFileChanged (dir </> $(mkRelFile "posts/pages/1/index.html")) (dir </> fp)

  "posts/tags/*/index.html" /%> \(dir, fp) -> do
    let t = (!! 2) $ splitPath fp
    i <- parseRelFile $ "posts/tags/" <> t <> "/pages/1/index.html"
    copyFileChanged (dir </> i) (dir </> fp)

  "posts/months/*/index.html" /%> \(dir, fp) -> do
    let t = (!! 2) $ splitPath fp
    i <- parseRelFile $ "posts/months/" <> t <> "/pages/1/index.html"
    copyFileChanged (dir </> i) (dir </> fp)

  ["css//*", "js//*", "webfonts//*", "images//*"] /|%> \(dir, fp) ->
    copyFileChanged (sourceFolder </> fp) (dir </> fp)

  "sitemap.xml" /%> \(dir, fp) -> do
    xs <- postIx' ()
    let xs' = Ix.toDescList (Proxy @Posted) xs
    buildSitemap (asSitemapUrl baseUrl <$> xs') $ dir </> fp

  let simplePipeline f = getDirectoryFiles sourceFolder >=> mapM f >=> needIn outputFolder
      verbatimPipeline = simplePipeline return

  phony "statics" $ verbatimPipeline ["css//*", "js//*", "webfonts//*", "images//*"]

  phony "index"   $ needIn outputFolder [$(mkRelFile "index.html")]

  phony "docs"    $ mapM withHtmlExtension tableOfContents >>= needIn outputFolder

  phony "posts"   $ simplePipeline withHtmlExtension ["posts/*.md"]

  let phonyIndex x y = do
        k  <- askOracle x
        ps <- askOracle y
        xs <- mapM fromGroundedUrlD $ k : (viewUrl <$> ps)
        needIn outputFolder $ fmap (</> $(mkRelFile "index.html")) xs

  phony "post-index" $ do
     phonyIndex (PostsRoot ()) (PostPages ())
     xs <- postIx' ()
     forM_ (Ix.indexKeys xs) $ \t -> phonyIndex (TagRoot t) (TagPages t)
     forM_ (Ix.indexKeys xs) $ \t -> phonyIndex (YearMonthRoot t) (YearMonthPages t)

  phony "clean" $ do
    logInfo $ "Cleaning files in " <> displayShow outputFolder
    removeFilesAfter outputFolder ["//*"]

  phony "sitemap" $ needIn outputFolder [$(mkRelFile "sitemap.xml")]

tests :: [FilePath] -> TestTree
tests xs = testGroup "Rendering Tests" $
  map ( \x -> goldenVsFile x x
     (replace "golden" "public" x)
     (return ())) xs
  where replace fr to' = intercalate to' . splitOn fr

main :: IO ()
main = do
   xs <- findByExtension [".html", ".xml"] "test/golden"
   logOptions' <- logOptionsHandle stdout True
   (lf, dlf) <- newLogFunc (setLogMinLevel LevelInfo logOptions')
   let env = SimpleSPlus lf outputFolder
   shake shakeOptions $ want ["clean"] >> runShakePlus env rules
   shake shakeOptions $ want ["index", "docs", "posts", "post-index", "sitemap"] >> runShakePlus env rules
   defaultMain $ tests xs
   dlf
