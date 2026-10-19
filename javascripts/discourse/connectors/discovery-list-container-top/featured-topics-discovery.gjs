import TlpFeaturedTopicsPlacement from "../../components/tlp-featured-topics-placement";

export default <template>
  <TlpFeaturedTopicsPlacement
    @category={{@outletArgs.category}}
    @placement="Above topic list"
  />
</template>
