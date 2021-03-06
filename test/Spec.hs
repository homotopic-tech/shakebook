{-# LANGUAGE TemplateHaskell #-}

import           Data.List.Split
import           Path.Extensions
import           RIO
import qualified RIO.ByteString.Lazy as LBS
import           RIO.List
import qualified RIO.Text            as T
import           Shakebook
import qualified Shakebook.IxSet     as Ix
import qualified Shakebook.Tuple     as C
import           Test.Tasty
import           Test.Tasty.Golden

-- Config --

sourceDir :: Path Rel Dir
sourceDir = $(mkRelDir "test/site")

outputDir :: Path Rel Dir
outputDir = $(mkRelDir "test/public")

templatesDir :: Path Rel Dir
templatesDir = $(mkRelDir "templates")

baseUrl :: Text
baseUrl = "http://blanky.test"

siteTitle :: Text
siteTitle = "Blanky Site"

tableOfContents :: Cofree [] (Path Rel File)
tableOfContents = $(mkRelFile "docs/index.md") :< [
                    $(mkRelFile "docs/1/index.md") :< []
                  , $(mkRelFile "docs/2/index.md") :< [
                  $(mkRelFile "docs/2/champ.md") :< []
                    ]
                  ]

numRecentPosts :: Int
numRecentPosts = 3

numPageNeighbours :: Int
numPageNeighbours = 3

postsPerPage :: Int
postsPerPage = 5

mySocial :: [Record Link]
mySocial = [ "twitter" :|: "http://twitter.com/blanky-site-nowhere"
           , "youtube" :|: "http://youtube.com/blanky-site-nowhere"
           , "gitlab"  :|: "http://gitlab.com/blanky-site-nowhere"
           ]

postsRoot :: Text
postsRoot = "/posts/"

tagRoot :: Tag -> Text
tagRoot x = "/posts/tags/" <> unTag x <> "/"

monthRoot :: YearMonth -> Text
monthRoot x = "/posts/months/" <> (defaultMonthUrlFormat . fromYearMonth $ x) <> "/"

pageRoot :: Text -> Int -> Text
pageRoot x i = x <> "pages/" <> (T.pack . show $ i) <> "/"

enrichment :: Record Enrichment
enrichment = val @"social"        mySocial
          :& val @"cdn-imports"   defaultCdnImports
          :& val @"highlighting"  defaultHighlighting
          :& val @"site-title"    siteTitle
          :& RNil

type PostSet = Ix.IxSet '[Tag, Posted, YearMonth] (Record (Routed Stage1Post))

-- Loaders

loadMarkdownWith :: (ShakeValue (Record (Compdoc a)), MonadSB r m) => JsonFormat Void (Record a) -> Path Rel File -> m (Record (Compdoc a))
loadMarkdownWith f x = cacheAction ("loader" :: Text, x) $ do
  logInfo $ "Loading " <> displayShow (toFilePath x)
  readMarkdownFile defaultMarkdownReaderOptions defaultHtml5WriterOptions f x

postIndex :: MonadSB r m => Path Rel Dir -> [FilePattern] -> m PostSet
postIndex = batchLoadIndex $ \x -> do
              k <- loadMarkdownWith rawPostMetaJsonFormat x
              u <- deriveUrl x
              return $ u :*: stage1PostExtras k <+> k

docTree :: MonadSB r m => Path Rel Dir -> Cofree [] (Path Rel File) -> m (Cofree [] (Record (Routed RawDoc)))
docTree dir toc' = forM (dir </$> toc') $ \x -> do
                     k <- loadMarkdownWith rawDocMetaJsonFormat x
                     u <- deriveUrl x
                     return $ u :*: k

-- Extras

deriveUrl :: MonadThrow m => Path Rel File -> m Text
deriveUrl = fmap toGroundedUrl . withHtmlExtension <=< stripProperPrefix sourceDir

mainPageExtras :: Ix.IsIndexOf Posted ixs => Ix.IxSet ixs (Record xs) -> Record (FRecentPosts xs : '[])
mainPageExtras = C.singleton . mostRecentPosted numRecentPosts

stage1PostExtras :: Record RawPost -> Record Stage1PostExtras
stage1PostExtras x = view fPosted x
                 :*: (map (deriveTagLink tagRoot . Tag) . view fTags $ x)
                 :*: (defaultDeriveTeaser . view fContent $ x)
                 :*: RNil

createBlogNav :: PostSet -> Cofree [] (Record Link)
createBlogNav xs = ("Blog" :*: postsRoot :*: RNil)
                :< Ix.toDescCofreeList
                    (C.fanout (defaultPrettyMonthFormat . fromYearMonth) monthRoot)
                    (C.fanout (view fTitle) (view fUrl))
                    (Down . view fPosted)
                    xs

-- Stache Builders

myBuildPage :: (MonadAction m, RMap x, RecordToJsonObject x, RecordFromJson x)
            => PName -> Rec (JsonField e) x -> Record x -> Path Rel File -> m ()
myBuildPage t f x out = do
  k <- compileMustacheDir' t (sourceDir </> templatesDir)
  let l' = renderMustache' k (enrichedRecordJsonFormat f) (enrichment <+> x)
  writeFile' out l'

buildFromRouteF t f x = do
  out <- fromGroundedUrlF $ view fUrl x
  myBuildPage t f (rcast x) (outputDir </> out)

buildFromRouteD t f x = do
  out <- deriveIndexHtmlF $ view fUrl x
  myBuildPage t f (rcast x) (outputDir </> out)

-- Rules

docsRules :: MonadSB r m => Path Rel Dir -> Cofree [] (Path Rel File) -> m ()
docsRules dir toc = do
  as <- docTree dir toc
  let nav = createDocNav as
  let as' = as =>> \(x :< xs) -> val @"toc" nav :& val @"subsections" (extract <$> xs) :& x
  forM_ as' $ buildFromRouteF "docs" finalDocJsonFields

mainPageRules :: MonadSB r m => PostSet -> m ()
mainPageRules postsIx = do
  x <- loadMarkdownWith rawSingleMetaJsonFormat $ sourceDir </> $(mkRelFile "index.md")
  let x' = mainPageExtras postsIx <+> x
  myBuildPage "index" mainPageJsonFields x' $ outputDir </> $(mkRelFile "index.html")

deriveIndexHtmlF :: MonadThrow m => Text -> m (Path Rel File)
deriveIndexHtmlF = fmap (</> $(mkRelFile "index.html")) . fromGroundedUrlD

postIndexRules :: MonadSB r m => Cofree [] (Record Link) -> Text -> PostSet -> Text -> m ()
postIndexRules nav title postset root = do
  ys <- indexPagesBy (Proxy @Posted) postsPerPage postset
  let ys' = flip fmap ys $ \x -> val @"url" (pageRoot root $ view fPageNo x) :& x
  sequence_ $ ys' =>> \xs' -> do
    let x = extract xs'
    ps <- toHtmlFragmentM $ renderPageLinks numPageNeighbours ys'
    let x' = val @"page-links" ps :& val @"toc" nav :& val @"title" title :& x
    buildFromRouteD "post-list" postIndexPageJsonFields x'
  k' <- deriveIndexHtmlF $ view fUrl $ extract $ seek 0 ys'
  s' <- deriveIndexHtmlF root
  copyFileChanged (outputDir </> k') (outputDir </> s')

postRules :: MonadSB r m => Path Rel Dir -> [FilePattern] -> m PostSet
postRules dir fp = cacheAction ("build" :: T.Text, (dir, fp)) $ do
  postsIx <- postIndex dir fp
  let nav = createBlogNav postsIx
  let postsZ = Ix.toDescList (Proxy @Posted) postsIx
  let postsZ' = fmap (\x -> val @"toc" nav :& x) postsZ
  forM_ postsZ' $ buildFromRouteF "post" finalPostJsonFields
  postIndexRules nav "Posts" postsIx postsRoot
  forM_ (Ix.indexKeys postsIx) $ \t@(Tag t') ->
    postIndexRules nav ("Posts tagged " <> t') (postsIx Ix.@+ [t]) (tagRoot t)
  forM_ (Ix.indexKeys postsIx) \ym@(YearMonth _) ->
    postIndexRules nav ("Posts from " <> defaultPrettyMonthFormat (fromYearMonth ym)) (postsIx Ix.@+ [ym]) (monthRoot ym)
  return postsIx

sitemapRules :: MonadSB r m => PostSet -> Path Rel File -> m ()
sitemapRules xs out = cacheAction ("sitemap" :: T.Text, out) $
  LBS.writeFile (toFilePath $ outputDir </> out) $ renderSitemap $ Sitemap $ asSitemapUrl baseUrl <$> Ix.toList xs

buildRules :: MonadSB r m => m ()
buildRules = do
  xs <- postRules sourceDir ["posts/*.md"]
  mainPageRules xs
  docsRules sourceDir tableOfContents
  sitemapRules xs $(mkRelFile "sitemap.xml")

tests :: [FilePath] -> TestTree
tests xs = testGroup "Rendering Tests" $
  map (\x -> goldenVsFile x x (replace "golden" "public" x) (return ())) xs where
    replace fr to' = intercalate to' . splitOn fr

main :: IO ()
main = do
  let shOpts = shakeOptions { shakeLintInside = ["\\"]}
  runLoggedShakeForward shOpts buildRules
  findByExtension [".html", ".xml"] "test/golden" >>= defaultMain . tests
