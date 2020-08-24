{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE UndecidableInstances #-}
{- |
   Module     : Shakebook.Conventions
   License    : MIT
   Stability  : experimental

Conventions used in Shakebook projects, common lenses, generators, and indexing wrappers over Values.
-}
module Shakebook.Conventions where

import           Composite.Aeson
import           Composite.Aeson.Path
import           Composite.Record
import           Composite.TH
import           Control.Comonad.Cofree
import           Control.Comonad.Store
import           Control.Comonad.Store.Zipper
import           Data.Binary.Instances.Time ()
import           Data.Hashable.Time
import           Data.IxSet.Typed           as Ix
import           Data.Vinyl                 hiding (RElem)
import           Data.Vinyl.TypeLevel
import           Development.Shake.Plus     hiding ((:->))
import           Lucid
import           RIO
import qualified RIO.Text                   as T
import           RIO.Time
import           Shakebook.Aeson
import qualified Shakebook.Feed             as Atom
import           Shakebook.Lucid
import           Shakebook.Sitemap
import           Shakebook.Utils

withLensesAndProxies [d|
  type FId            = "id"           :-> Text
  type FUrl           = "url"          :-> Text
  |]

type Link = '[FId, FUrl]

linkJsonFormat :: JsonFormat e (Record Link)
linkJsonFormat = recordJsonFormat $ field textJsonFormat :& field textJsonFormat :& RNil

withLensesAndProxies [d|
  type FCdnImports    = "cdn-imports"  :-> HtmlFragment
  type FContent       = "content"      :-> Text
  type FDescription   = "description"  :-> Text
  type FHighlighting  = "highlighting" :-> StyleFragment
  type FImage         = "image"        :-> Maybe Text
  type FItems x       = "items"        :-> [Record x]
  type FModified      = "modified"     :-> UTCTime
  type FNext          = "next"         :-> HtmlFragment
  type FPageLinks     = "page-links"   :-> HtmlFragment
  type FPageNo        = "pageno"       :-> Int
  type FPrettyDate    = "pretty-date"  :-> UTCTime
  type FPrevious      = "previous"     :-> HtmlFragment
  type FPosted        = "posted"       :-> UTCTime
  type FRecentPosts x = "recent-posts" :-> [Record x]
  type FSiteTitle     = "site-title"   :-> Text
  type FSrcPath       = "src-path"     :-> Path Rel File
  type FSocialLinks   = "social-links" :-> [Record Link]
  type FSubsections x = "subsections"  :-> [Record x]
  type FTags          = "tags"         :-> [Text]
  type FTagLinks      = "tag-links"    :-> [Record Link]
  type FTeaser        = "teaser"       :-> Text
  type FTitle         = "title"        :-> Text
  type FToc           = "toc"          :-> HtmlFragment
  |]

sbDisplayDateTimeJsonFormat :: JsonFormat e UTCTime
sbDisplayDateTimeJsonFormat = dateTimeJsonFormat defaultTimeLocale (regularDateTimeFormat "%A, %B %d, %Y" "yyyy-mm-dd" :| [])

sbShortDateJsonFormat :: JsonFormat e UTCTime
sbShortDateJsonFormat = dateTimeJsonFormat defaultTimeLocale (regularDateTimeFormat "%F" "yyyy-mm-dd" :| [])

type BasicMD = FSrcPath : FContent : '[]

type RawDoc = FModified : FTitle : FDescription : BasicMD

type RawPost = FPosted : FImage : FTitle : FTags : BasicMD

type RawSingle = FImage : FTitle : BasicMD

type Stage1Post = FPrettyDate : FTagLinks : FTeaser : FUrl : RawPost

type Stage1Doc = FUrl : RawDoc

type IndexPage x = FPageLinks : FToc : FTitle : FUrl : FItems x : FPageNo : '[]

type PostIndexPage = IndexPage Stage1Post

type FinalDoc = FToc : FSubsections Stage1Doc : Stage1Doc

type FinalPost = FToc : Stage1Post

type MainPage = FRecentPosts Stage1Post : RawSingle

-- | Tag indices for a `Post` for use with `IxSet`.
newtype Tag = Tag { unTag :: Text }
  deriving stock   (Show, Eq, Ord, Data, Typeable, Generic)
  deriving newtype (Hashable, Binary, NFData)

-- | Posted index for a `Post` for use with `IxSet`.
newtype Posted = Posted { unPosted :: UTCTime }
  deriving stock   (Show, Eq, Ord, Data, Typeable, Generic)
  deriving newtype (Hashable, Binary, NFData)

-- | YearMonth (yyyy, mm) index for a `Post` for use with `IxSet`.
newtype YearMonth = YearMonth { unYearMonth :: (Integer, Int) }
  deriving stock   (Show, Eq, Ord, Data, Typeable, Generic)
  deriving newtype (Hashable, Binary, NFData)

toYearMonth :: UTCTime -> YearMonth
toYearMonth = (\(a, b, _) -> YearMonth (a, b)) . toGregorian . utctDay

fromYearMonth :: YearMonth -> UTCTime
fromYearMonth (YearMonth (y,m)) = UTCTime (fromGregorian y m 1) 0

deriveTagLink :: Monad m => (Tag -> m Text) -> Tag -> m (Record Link)
deriveTagLink f x = rtraverseToSnd (f . Tag) (unTag x)

type PostSet = Ix.IxSet '[Tag, Posted, YearMonth] (Record Stage1Post)

instance Ix.Indexable '[Tag, Posted, YearMonth] (Record Stage1Post) where
  indices = Ix.ixList (Ix.ixFun (fmap Tag . view fTags))
                      (Ix.ixFun (pure . Posted . view fPosted))
                      (Ix.ixFun (pure . toYearMonth . view fPosted))

asSitemapUrl :: (RElem FUrl xs, RElem FPosted xs) => Text -> Record xs -> SitemapUrl
asSitemapUrl baseUrl x = SitemapUrl {
   sitemapLocation = baseUrl <> view fUrl x
 , sitemapLastModified = Just (view fPosted x)
 , sitemapChangeFrequency = Nothing
 , sitemapPriority = Nothing
}

-- | Convert a Post to an Atom Entry
asAtomEntry :: (RElem FContent xs, RElem FPosted xs, RElem FUrl xs, RElem FTitle xs) => Record xs -> Atom.Entry
asAtomEntry x = (Atom.nullEntry (view fUrl x)
                  (Atom.TextString $ view fTitle x)
                  (T.pack $ formatTime defaultTimeLocale (iso8601DateFormat Nothing) $ view fPosted x)) {
                    Atom.entryContent = Just $ Atom.TextContent (view fContent x)
                  }

renderTitleLink :: (Monad m, RElem FTitle xs, RElem FUrl xs) => Record xs -> HtmlT m ()
renderTitleLink = liftA2 renderLink (view fTitle) (view fUrl)

renderDocNav :: (Monad m, RElem FTitle xs, RElem FUrl xs) => Cofree [] (Record xs) -> HtmlT m ()
renderDocNav xs = ul_ $ li_ $ renderCofree renderTitleLink xs

renderPageLinks :: (RElem FPageNo xs, RElem FUrl xs, MonadThrow m) => Int -> Zipper [] (Record xs) -> HtmlT m ()
renderPageLinks = renderZipperWithin (liftA2 renderLink (T.pack . show . view fPageNo) (view fUrl))

type BasicFields = FContent
                 : FDescription
                 : FImage
                 : FModified
                 : FPosted
                 : FSrcPath
                 : FTags
                 : FTitle
                 : FUrl
                 : '[]

basicFields :: Rec (JsonField e) BasicFields
basicFields = (field textJsonFormat                  :: JsonField e FContent)
           :& (field textJsonFormat                  :: JsonField e FDescription)
           :& (optionalField textJsonFormat          :: JsonField e FImage)
           :& (field iso8601DateTimeJsonFormat       :: JsonField e FModified)
           :& (field sbShortDateJsonFormat           :: JsonField e FPosted)
           :& (field relFileJsonFormat               :: JsonField e FSrcPath)
           :& (field (listJsonFormat textJsonFormat) :: JsonField e FTags)
           :& (field textJsonFormat                  :: JsonField e FTitle)
           :& (field textJsonFormat                  :: JsonField e FUrl)
           :& RNil

type ExtraFields = FCdnImports
                 : FHighlighting
                 : FPageLinks
                 : FPageNo
                 : FPrettyDate
                 : FSiteTitle
                 : FSocialLinks
                 : FTagLinks
                 : FTeaser
                 : FToc
                 : '[]

extraFields :: Rec (JsonField e) ExtraFields
extraFields =  (field htmlJsonFormat                  :: JsonField e FCdnImports)
            :& (field styleJsonFormat                 :: JsonField e FHighlighting)
            :& (field htmlJsonFormat                  :: JsonField e FPageLinks)
            :& (field integralJsonFormat              :: JsonField e FPageNo)
            :& (field sbDisplayDateTimeJsonFormat     :: JsonField e FPrettyDate)
            :& (field textJsonFormat                  :: JsonField e FSiteTitle)
            :& (field (listJsonFormat linkJsonFormat) :: JsonField e FSocialLinks)
            :& (field (listJsonFormat linkJsonFormat) :: JsonField e FTagLinks)
            :& (field textJsonFormat                  :: JsonField e FTeaser)
            :& (field htmlJsonFormat                  :: JsonField e FToc)
            :& RNil

listCastElemsFormat :: (RMap a, RecordToJsonObject a, RecordFromJson a, a <: b) => JsonFormatRecord e b -> JsonFormat e [Record a]
listCastElemsFormat = listJsonFormat . recordJsonFormat . rcast

type CompositeFields = FItems Stage1Post
                     : FSubsections Stage1Doc
                     : FRecentPosts Stage1Post
                     : '[]

compositeFields :: Rec (JsonField e) CompositeFields
compositeFields = let x = extraFields <+> basicFields
                  in (field (listCastElemsFormat x) :: JsonField e (FItems Stage1Post))
                 :& (field (listCastElemsFormat x) :: JsonField e (FSubsections Stage1Doc))
                 :& (field (listCastElemsFormat x) :: JsonField e (FRecentPosts Stage1Post))
                 :& RNil

type StandardFields = BasicFields ++ ExtraFields ++ CompositeFields

allFields :: Rec (JsonField e) StandardFields
allFields = basicFields <+> extraFields <+> compositeFields

rawPostJsonFormat :: JsonFormat e (Record RawPost)
rawPostJsonFormat = recordJsonFormat $ rcast basicFields

rawDocJsonFormat :: JsonFormat e (Record RawDoc)
rawDocJsonFormat = recordJsonFormat $ rcast basicFields

rawSingleJsonFormat :: JsonFormat e (Record RawSingle)
rawSingleJsonFormat = recordJsonFormat $ rcast basicFields
